import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/flatpak_bloc.dart';
import '../data/flatpak_repository.dart';
import '../models/flatpak_package.dart';
import '../platform/flatpak_platform.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class InstalledAppsPage extends StatefulWidget {
  const InstalledAppsPage({super.key});

  @override
  State<InstalledAppsPage> createState() => _InstalledAppsPageState();
}

class _InstalledAppsPageState extends State<InstalledAppsPage> {
  List<FlatpakPackage> _installedApps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInstalledApps();
  }

  Future<void> _loadInstalledApps() async {
    final repo = context.read<FlatpakRepository>();
    final apps = await repo.getInstalledAppsRobust();

    if (!mounted) return;

    setState(() {
      _installedApps = apps;
      _isLoading = false;
    });

    repo.enrichMissingDetails(apps);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<FlatpakBloc, FlatpakState>(
      listenWhen: (prev, curr) {
        if (prev is FlatpakLoaded && curr is FlatpakLoaded) {
          return prev.installed != curr.installed;
        }
        return false;
      },
      listener: (context, state) {
        if (state is FlatpakLoaded) {
          final installedSet = state.installed;
          setState(() {
            _installedApps.removeWhere(
              (app) => !installedSet.contains(app.id),
            );
          });
        }
      },
      child: BlocBuilder<FlatpakBloc, FlatpakState>(
        buildWhen: (prev, curr) {
          if (prev.runtimeType != curr.runtimeType) return true;
          if (prev is FlatpakLoaded && curr is FlatpakLoaded) {
            return prev.uninstallingIds != curr.uninstallingIds;
          }
          return true;
        },
        builder: (context, state) {
          final uninstallingIds = state is FlatpakLoaded
              ? state.uninstallingIds
              : const <String>{};

          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.pageGutter,
                              AppSpacing.lg,
                              AppSpacing.pageGutter,
                              AppSpacing.xxl,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Installed apps',
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  '${_installedApps.length} app${_installedApps.length == 1 ? "" : "s"} on your device',
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_installedApps.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.huge),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding:
                                          const EdgeInsets.all(AppSpacing.xl),
                                      decoration: const BoxDecoration(
                                        color: AppColors.brandSoft,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.inbox_rounded,
                                        size: 36,
                                        color: AppColors.brand,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    Text(
                                      'No apps installed',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      'Browse the home screen to install your first app.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.pageGutter,
                            ),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final app = _installedApps[index];
                                  final isUninstalling =
                                      uninstallingIds.contains(app.id);

                                  return RepaintBoundary(
                                    key: ValueKey(app.id),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppSpacing.md,
                                      ),
                                      child: _InstalledAppCard(
                                        app: app,
                                        isUninstalling: isUninstalling,
                                        onLaunch: () async {
                                          try {
                                            await FlatpakPlatform.launch(
                                                app.id);
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Launch failed: $e'),
                                              ),
                                            );
                                          }
                                        },
                                        onUninstall: () {
                                          context
                                              .read<FlatpakBloc>()
                                              .add(UninstallApp(app.id));
                                        },
                                      ),
                                    ),
                                  );
                                },
                                childCount: _installedApps.length,
                                addAutomaticKeepAlives: false,
                              ),
                            ),
                          ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppSpacing.huge),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// =======================================================
/// CARD
/// =======================================================
class _InstalledAppCard extends StatelessWidget {
  final FlatpakPackage app;
  final bool isUninstalling;
  final VoidCallback onLaunch;
  final VoidCallback onUninstall;

  const _InstalledAppCard({
    required this.app,
    required this.isUninstalling,
    required this.onLaunch,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = AppColors.gradientFor(app.id);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          // Icon tile
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: gradient.last.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: app.icon != null
                  ? CachedNetworkImage(
                      imageUrl: app.icon!,
                      width: 36,
                      height: 36,
                      memCacheWidth: 72,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Icon(
                        Icons.apps_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.apps_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.apps_rounded,
                      size: 36,
                      color: Colors.white,
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'v${app.version ?? "Latest"}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // Actions
          IconButton(
            onPressed: onLaunch,
            tooltip: 'Launch',
            icon: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: AppColors.brand,
                size: 20,
              ),
            ),
          ),
          IconButton(
            onPressed: isUninstalling ? null : onUninstall,
            tooltip: 'Uninstall',
            icon: isUninstalling
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.danger,
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger,
                      size: 20,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
