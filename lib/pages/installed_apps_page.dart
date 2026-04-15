import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/flatpak_bloc.dart';
import '../data/flatpak_repository.dart';
import '../models/flatpak_package.dart';
import '../platform/flatpak_platform.dart';
import '../services/user_log.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class InstalledAppsPage extends StatefulWidget {
  const InstalledAppsPage({super.key});
  @override
  State<InstalledAppsPage> createState() => _InstalledAppsPageState();
}

class _InstalledAppsPageState extends State<InstalledAppsPage> {
  List<FlatpakPackage> _apps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<FlatpakRepository>();
    final apps = await repo.getInstalledAppsRobust();
    if (!mounted) return;
    setState(() { _apps = apps; _loading = false; });
    repo.enrichMissingDetails(apps);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<FlatpakBloc, FlatpakState>(
      listenWhen: (p, c) {
        if (p is FlatpakLoaded && c is FlatpakLoaded) {
          return p.installed != c.installed;
        }
        return false;
      },
      listener: (_, state) {
        if (state is FlatpakLoaded) {
          final set = state.installed;
          // `installed` is a set of normalized flatpak refs; the local
          // list may carry either form depending on cache provenance,
          // so treat absence from *both* forms as "uninstalled".
          setState(() => _apps.removeWhere(
              (a) => !set.contains(a.flatpakId) && !set.contains(a.id)));
        }
      },
      child: BlocBuilder<FlatpakBloc, FlatpakState>(
        buildWhen: (p, c) {
          if (p.runtimeType != c.runtimeType) return true;
          if (p is FlatpakLoaded && c is FlatpakLoaded) {
            return p.uninstallingIds != c.uninstallingIds;
          }
          return true;
        },
        builder: (context, state) {
          final uninstalling = state is FlatpakLoaded
              ? state.uninstallingIds : const <String>{};

          return Scaffold(
            backgroundColor: context.colors.bg,
            body: SafeArea(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.brand))
                  : CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                                AppSpacing.pageH, AppSpacing.lg,
                                AppSpacing.pageH, AppSpacing.xxl),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Installed',
                                    style: Theme.of(context)
                                        .textTheme.displaySmall),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  '${_apps.length} app${_apps.length == 1 ? "" : "s"}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_apps.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(AppSpacing.xl),
                                    decoration: const BoxDecoration(
                                        color: AppColors.brandSoft,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.inbox_rounded,
                                        size: 36, color: AppColors.brand),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  Text('No apps installed',
                                      style: Theme.of(context)
                                          .textTheme.titleLarge),
                                ],
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.pageH),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (_, i) {
                                  final app = _apps[i];
                                  final grad = AppColors.gradientFor(app.id);
                                  // Match against flatpakId since the bloc's
                                  // uninstallingIds set stores normalized
                                  // flatpak refs, not PensHub's internal id.
                                  final removing =
                                      uninstalling.contains(app.flatpakId) ||
                                          uninstalling.contains(app.id);

                                  return RepaintBoundary(
                                    key: ValueKey(app.id),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: AppSpacing.md),
                                      child: Container(
                                        padding:
                                            const EdgeInsets.all(AppSpacing.lg),
                                        decoration: BoxDecoration(
                                          color: context.colors.card,
                                          borderRadius: BorderRadius.circular(
                                              AppSpacing.rLg),
                                          border: Border.all(
                                              color: context.colors.border),
                                        ),
                                        child: Row(children: [
                                          Container(
                                            width: 56, height: 56,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppSpacing.rMd),
                                              gradient: LinearGradient(
                                                  colors: grad),
                                            ),
                                            child: Center(
                                              child: app.icon != null
                                                  ? CachedNetworkImage(
                                                      imageUrl: app.icon!,
                                                      width: 32, height: 32,
                                                      memCacheWidth: 64,
                                                      fit: BoxFit.contain,
                                                      placeholder: (_, __) =>
                                                          const Icon(
                                                              Icons
                                                                  .apps_rounded,
                                                              color: Colors
                                                                  .white),
                                                      errorWidget:
                                                          (_, __, ___) =>
                                                              const Icon(
                                                                  Icons
                                                                      .apps_rounded,
                                                                  color: Colors
                                                                      .white))
                                                  : const Icon(
                                                      Icons.apps_rounded,
                                                      color: Colors.white),
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.lg),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(app.name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow
                                                        .ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium),
                                                const SizedBox(height: 2),
                                                Text(
                                                    'v${app.version ?? "Latest"}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall),
                                              ],
                                            ),
                                          ),
                                          // Launch
                                          GestureDetector(
                                            onTap: () async {
                                              UserLog.tap('installed.launch',
                                                  {'id': app.flatpakId});
                                              try {
                                                await FlatpakPlatform.launch(
                                                    app.id);
                                              } catch (e) {
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                        content: Text(
                                                            'Launch failed: $e')));
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(
                                                  AppSpacing.sm),
                                              decoration: BoxDecoration(
                                                color: AppColors.brandSoft,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AppSpacing.rSm),
                                              ),
                                              child: const Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: AppColors.brand,
                                                  size: 20),
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          // Uninstall
                                          GestureDetector(
                                            onTap: removing
                                                ? null
                                                : () {
                                                    UserLog.tap(
                                                        'installed.uninstall',
                                                        {'id': app.flatpakId});
                                                    context
                                                        .read<FlatpakBloc>()
                                                        .add(UninstallApp(
                                                            app.flatpakId));
                                                  },
                                            child: removing
                                                ? const SizedBox(
                                                    width: 20, height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: AppColors
                                                                .danger))
                                                : Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            AppSpacing.sm),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.danger
                                                          .withValues(
                                                              alpha: 0.12),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              AppSpacing.rSm),
                                                    ),
                                                    child: const Icon(
                                                        Icons
                                                            .delete_outline_rounded,
                                                        color: AppColors.danger,
                                                        size: 20),
                                                  ),
                                          ),
                                        ]),
                                      ),
                                    ),
                                  );
                                },
                                childCount: _apps.length,
                                addAutomaticKeepAlives: false,
                              ),
                            ),
                          ),
                        const SliverToBoxAdapter(
                            child: SizedBox(height: AppSpacing.huge)),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}
