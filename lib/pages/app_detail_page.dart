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
    final n = raw.replaceAll('_', '.');
    if (_looksLikeFlatpakId(n)) return n;
    return raw;
  }

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  late FlatpakPackage _pkg;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _pkg = widget.package;
    _refresh();
  }

  Future<void> _refresh() async {
    if ((_pkg.description?.isNotEmpty ?? false) && _pkg.screenshots.isNotEmpty) {
      return;
    }
    setState(() => _fetching = true);
    try {
      final repo = context.read<FlatpakRepository>();
      final fresh =
          await repo.fetchDetailsByFlatpakId(_pkg.flatpakId, forceRefresh: true);
      if (!mounted || fresh == null) return;
      setState(() => _pkg = fresh);
    } catch (_) {}
    if (mounted) setState(() => _fetching = false);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FlatpakBloc, FlatpakState>(
      buildWhen: (p, c) {
        if (p.runtimeType != c.runtimeType) return true;
        if (p is FlatpakLoaded && c is FlatpakLoaded) {
          final id = AppDetailPage.normalizeFlatpakId(_pkg.flatpakId);
          return p.installed.contains(id) != c.installed.contains(id) ||
              p.installingIds.contains(id) != c.installingIds.contains(id) ||
              p.installProgress[id] != c.installProgress[id];
        }
        return true;
      },
      builder: (context, state) {
        bool installed = false;
        bool installing = false;
        int? progress;
        if (state is FlatpakLoaded) {
          final id = AppDetailPage.normalizeFlatpakId(_pkg.flatpakId);
          installed = state.installed.contains(id);
          installing = state.installingIds.contains(id);
          progress = state.installProgress[id];
        }

        final grad = AppColors.gradientFor(_pkg.id);
        final id = AppDetailPage.normalizeFlatpakId(_pkg.flatpakId);

        return Scaffold(
          backgroundColor: context.colors.bg,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.card.withValues(alpha: 0.80),
                    shape: BoxShape.circle,
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Icon(Icons.arrow_back_rounded,
                      color: context.colors.textP),
                ),
              ),
            ),
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HERO with bottom fade — shorter on narrow portrait screens
                LayoutBuilder(builder: (context, box) {
                  final heroH = box.maxWidth < 400 ? 220.0 : 300.0;
                  return SizedBox(height: heroH,
                  child: Stack(
                    children: [
                      // Gradient background
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: grad,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                      ),
                      // Decorative circles
                      Positioned(
                        top: -50, right: -40,
                        child: Container(
                          width: 200, height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 20, left: -30,
                        child: Container(
                          width: 100, height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      // Bottom gradient fade into background
                      Positioned(
                        left: 0, right: 0, bottom: 0, height: 60,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                context.colors.bg,
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Icon
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppSpacing.rXxl),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.20)),
                          ),
                          child: _pkg.icon != null
                              ? CachedNetworkImage(
                                  imageUrl: _pkg.icon!, width: 80, height: 80,
                                  memCacheWidth: 160, fit: BoxFit.contain,
                                  placeholder: (_, __) => const Icon(
                                      Icons.apps_rounded, size: 80,
                                      color: Colors.white54),
                                  errorWidget: (_, __, ___) => const Icon(
                                      Icons.apps_rounded, size: 80,
                                      color: Colors.white54),
                                )
                              : const Icon(Icons.apps_rounded, size: 80,
                                  color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ); }),

                // HEADER
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageH, AppSpacing.xxl, AppSpacing.pageH, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_pkg.name,
                          style: Theme.of(context).textTheme.displaySmall),
                      if (_pkg.developerName != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text('by ${_pkg.developerName}',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                      if (_pkg.summary != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(_pkg.summary!,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: context.colors.textS)),
                      ],
                    ],
                  ),
                ),

                // META PILLS
                if (_pkg.version != null || _pkg.license != null ||
                    _pkg.categories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageH, AppSpacing.lg, AppSpacing.pageH, 0),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        if (_pkg.version != null)
                          _Pill(Icons.tag_rounded, _pkg.version!,
                              accent: AppColors.accentCyan),
                        if (_pkg.license != null)
                          _Pill(Icons.gavel_rounded, _pkg.license!,
                              accent: AppColors.accentGreen),
                        for (final c in _pkg.categories.take(2))
                          _Pill(Icons.label_rounded, c,
                              accent: AppColors.brandLight),
                      ],
                    ),
                  ),

                // DESCRIPTION
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageH, AppSpacing.xxl, AppSpacing.pageH, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('About',
                            style: Theme.of(context).textTheme.titleLarge),
                        if (_fetching) ...[
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: context.colors.textT)),
                        ],
                      ]),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _pkg.description ?? _pkg.summary ?? 'No description available.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),

                // SCREENSHOTS
                if (_pkg.screenshots.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageH, AppSpacing.xxxl, AppSpacing.pageH, AppSpacing.md),
                    child: Text('Screenshots',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  SizedBox(
                    height: 220,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                      itemCount: _pkg.screenshots.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppSpacing.md),
                      itemBuilder: (_, i) => RepaintBoundary(
                        key: ValueKey('ss_$i'),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppSpacing.rMd),
                          child: CachedNetworkImage(
                            imageUrl: _pkg.screenshots[i],
                            width: 300, height: 220,
                            memCacheWidth: 600, fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                                width: 300, height: 220,
                                color: context.colors.cardEl),
                            errorWidget: (_, __, ___) => Container(
                                width: 300, height: 220,
                                color: context.colors.cardEl,
                                child: Icon(Icons.broken_image_rounded,
                                    color: context.colors.textT)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 120),
              ],
            ),
          ),

          // BOTTOM ACTION
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.pageH),
              child: SizedBox(
                height: AppSpacing.touchLg,
                child: Material(
                  borderRadius: BorderRadius.circular(AppSpacing.rLg),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSpacing.rLg),
                      gradient: installed
                          ? null
                          : LinearGradient(colors: grad),
                      color: installed ? context.colors.card : null,
                      border: installed
                          ? Border.all(color: context.colors.border)
                          : null,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppSpacing.rLg),
                      onTap: installing
                          ? null
                          : installed
                              ? () => FlatpakPlatform.launch(id)
                              : () => context.read<FlatpakBloc>().add(InstallApp(id)),
                      child: Center(
                        child: installing
                            ? Row(mainAxisSize: MainAxisSize.min, children: [
                                const SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white)),
                                const SizedBox(width: AppSpacing.md),
                                Text(
                                  progress != null
                                      ? 'Installing $progress%' : 'Installing...',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 22,
                                      fontWeight: FontWeight.w700),
                                ),
                              ])
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(
                                  installed
                                      ? Icons.play_arrow_rounded
                                      : Icons.download_rounded,
                                  color: installed
                                      ? context.colors.textP : Colors.white,
                                  size: 22),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  installed ? 'Launch' : 'Install',
                                  style: TextStyle(
                                      color: installed
                                          ? context.colors.textP : Colors.white,
                                      fontSize: 22, fontWeight: FontWeight.w700),
                                ),
                              ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  const _Pill(this.icon, this.label, {this.accent = AppColors.textSecondary});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.rFull),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: accent),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: accent)),
      ]),
    );
  }
}
