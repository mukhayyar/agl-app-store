import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/flatpak_bloc.dart';
import '../data/flatpak_repository.dart';
import '../models/flatpak_package.dart';
import '../platform/flatpak_platform.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class AppDetailPage extends StatefulWidget {
  final FlatpakPackage package;

  const AppDetailPage({super.key, required this.package});

  // Pre-compiled static RegExp
  static final _partRe = RegExp(r'^[A-Za-z0-9_]+$');
  static final _lastPartRe = RegExp(r'^[A-Za-z0-9_-]+$');

  static bool _looksLikeFlatpakId(String id) {
    if (!id.contains('.')) return false;
    final parts = id.split('.');
    for (int i = 0; i < parts.length; i++) {
      final isLast = i == parts.length - 1;
      if (!(isLast ? _lastPartRe : _partRe).hasMatch(parts[i])) return false;
    }
    return true;
  }

  static String normalizeFlatpakId(String raw) {
    if (raw.isEmpty) return raw;
    if (_looksLikeFlatpakId(raw)) return raw;

    final normalized = raw.replaceAll('_', '.');
    if (_looksLikeFlatpakId(normalized)) return normalized;

    return raw;
  }

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  /// Local copy of the package — starts as the one passed by the caller and
  /// gets replaced by a fresh, fully-hydrated version once the API responds.
  late FlatpakPackage _package;
  bool _isFetchingDetails = false;

  @override
  void initState() {
    super.initState();
    _package = widget.package;
    _refreshDetails();
  }

  /// Always pulls fresh details from the active source so the user sees the
  /// real description, screenshots and metadata even if the list view's copy
  /// was a stub created during initial pagination.
  Future<void> _refreshDetails() async {
    final needsRefresh = (_package.description == null ||
            _package.description!.isEmpty) ||
        _package.screenshots.isEmpty ||
        _package.developerName == null;

    if (!needsRefresh) return;

    setState(() => _isFetchingDetails = true);
    try {
      final repo = context.read<FlatpakRepository>();
      final fresh = await repo.fetchDetailsByFlatpakId(
        _package.flatpakId,
        forceRefresh: true,
      );
      if (!mounted || fresh == null) return;
      setState(() => _package = fresh);
    } catch (_) {
      // Silent fail — we still show whatever we already had.
    } finally {
      if (mounted) {
        setState(() => _isFetchingDetails = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FlatpakBloc, FlatpakState>(
      buildWhen: (prev, curr) {
        if (prev.runtimeType != curr.runtimeType) return true;
        if (prev is FlatpakLoaded && curr is FlatpakLoaded) {
          final id = AppDetailPage.normalizeFlatpakId(_package.flatpakId);
          final prevInstalled = prev.installed.contains(id);
          final currInstalled = curr.installed.contains(id);
          final prevInstalling = prev.installingIds.contains(id);
          final currInstalling = curr.installingIds.contains(id);
          final prevProgress = prev.installProgress[id];
          final currProgress = curr.installProgress[id];
          return prevInstalled != currInstalled ||
              prevInstalling != currInstalling ||
              prevProgress != currProgress;
        }
        return true;
      },
      builder: (context, state) {
        bool isInstalled = false;
        bool isInstalling = false;
        int? progress;

        if (state is FlatpakLoaded) {
          final id = AppDetailPage.normalizeFlatpakId(_package.flatpakId);
          isInstalled = state.installed.contains(id);
          isInstalling = state.installingIds.contains(id);
          progress = state.installProgress[id];
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Material(
                color: Colors.white.withValues(alpha: 0.85),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _hero(),
                const SizedBox(height: AppSpacing.xxl),
                _header(context),
                const SizedBox(height: AppSpacing.lg),
                _meta(context),
                const SizedBox(height: AppSpacing.xxl),
                _description(context),
                if (_package.screenshots.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxxl),
                  _screenshots(context),
                ],
                if (_package.homepage != null) ...[
                  const SizedBox(height: AppSpacing.xxxl),
                  _links(context),
                ],
                const SizedBox(height: AppSpacing.huge),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.pageGutter),
              child: _actionButton(
                context,
                isInstalled: isInstalled,
                isInstalling: isInstalling,
                progress: progress,
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================
  // HERO
  // =========================
  Widget _hero() {
    final gradient = AppColors.gradientFor(_package.id);
    return Container(
      height: 320,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: _package.icon != null
                  ? CachedNetworkImage(
                      imageUrl: _package.icon!,
                      height: 96,
                      width: 96,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Icon(
                        Icons.apps_rounded,
                        size: 96,
                        color: Colors.white70,
                      ),
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.apps_rounded,
                        size: 96,
                        color: Colors.white70,
                      ),
                    )
                  : const Icon(
                      Icons.apps_rounded,
                      size: 96,
                      color: Colors.white70,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // HEADER
  // =========================
  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _package.name,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          if (_package.developerName != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'by ${_package.developerName}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (_package.summary != null && _package.summary!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _package.summary!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================
  // META (version, license, categories)
  // =========================
  Widget _meta(BuildContext context) {
    final pills = <Widget>[
      if (_package.version != null && _package.version!.isNotEmpty)
        _MetaPill(icon: Icons.tag_rounded, label: _package.version!),
      if (_package.license != null && _package.license!.isNotEmpty)
        _MetaPill(icon: Icons.gavel_rounded, label: _package.license!),
      for (final cat in _package.categories.take(3))
        _MetaPill(icon: Icons.label_rounded, label: cat),
    ];

    if (pills.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageGutter),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: pills,
      ),
    );
  }

  // =========================
  // DESCRIPTION
  // =========================
  Widget _description(BuildContext context) {
    final hasDescription =
        _package.description != null && _package.description!.isNotEmpty;
    final hasSummary =
        _package.summary != null && _package.summary!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('About this app',
                  style: Theme.of(context).textTheme.titleLarge),
              if (_isFetchingDetails) ...[
                const SizedBox(width: AppSpacing.md),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasDescription)
            Text(
              _package.description!,
              style: Theme.of(context).textTheme.bodyLarge,
            )
          else if (hasSummary && !_isFetchingDetails)
            Text(
              _package.summary!,
              style: Theme.of(context).textTheme.bodyLarge,
            )
          else if (_isFetchingDetails)
            _DescriptionSkeleton()
          else
            Text(
              'No description available.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }

  // =========================
  // SCREENSHOTS
  // =========================
  Widget _screenshots(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.pageGutter),
          child: Text('Screenshots',
              style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: 240,
          child: ListView.separated(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.pageGutter),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _package.screenshots.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              return RepaintBoundary(
                key: ValueKey('screenshot_$i'),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    child: CachedNetworkImage(
                      imageUrl: _package.screenshots[i],
                      width: 320,
                      height: 240,
                      memCacheWidth: 640,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 320,
                        height: 240,
                        color: AppColors.surfaceMuted,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 320,
                        height: 240,
                        color: AppColors.surfaceMuted,
                        child: const Icon(Icons.broken_image_rounded),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================
  // LINKS (homepage, bugtracker)
  // =========================
  Widget _links(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Links', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          if (_package.homepage != null)
            _LinkRow(
              icon: Icons.public_rounded,
              label: 'Homepage',
              url: _package.homepage!,
            ),
          if (_package.bugtracker != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _LinkRow(
              icon: Icons.bug_report_rounded,
              label: 'Bug tracker',
              url: _package.bugtracker!,
            ),
          ],
        ],
      ),
    );
  }

  // =========================
  // ACTION BUTTON
  // =========================
  Widget _actionButton(
    BuildContext context, {
    required bool isInstalled,
    required bool isInstalling,
    required int? progress,
  }) {
    final id = AppDetailPage.normalizeFlatpakId(_package.flatpakId);
    final gradient = AppColors.gradientFor(_package.id);

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        color: isInstalled ? AppColors.surface : null,
        elevation: 0,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            gradient: isInstalled
                ? null
                : LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            border: isInstalled
                ? Border.all(color: AppColors.borderSubtle)
                : null,
            boxShadow: isInstalled
                ? null
                : [
                    BoxShadow(
                      color: gradient.last.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            onTap: isInstalling
                ? null
                : isInstalled
                    ? () => FlatpakPlatform.launch(id)
                    : () => context.read<FlatpakBloc>().add(InstallApp(id)),
            child: Center(
              child: isInstalling
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          progress != null
                              ? 'Installing $progress%'
                              : 'Installing…',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isInstalled
                              ? Icons.play_arrow_rounded
                              : Icons.download_rounded,
                          color: isInstalled
                              ? AppColors.textPrimary
                              : Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          isInstalled ? 'Launch' : 'Install',
                          style: TextStyle(
                            color: isInstalled
                                ? AppColors.textPrimary
                                : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.brand),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Three skeleton lines shown while we fetch the real description so the
/// "About this app" section doesn't briefly display "No description available".
class _DescriptionSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget line(double widthFactor) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(1.0),
        const SizedBox(height: AppSpacing.sm),
        line(0.95),
        const SizedBox(height: AppSpacing.sm),
        line(0.7),
      ],
    );
  }
}
