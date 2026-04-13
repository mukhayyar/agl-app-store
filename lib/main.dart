import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'bloc/flatpak_bloc.dart';
import 'data/flatpak_repository.dart';
import 'models/app_source.dart';
import 'models/flatpak_package.dart';
import 'pages/category_page.dart';
import 'pages/app_detail_page.dart';
import 'pages/installed_apps_page.dart';
import 'pages/settings_page.dart';
import 'pages/monitor_page.dart';
import 'platform/flatpak_platform.dart';
import 'services/system_monitor.dart';
import 'services/gps_service.dart';
import 'services/api_benchmark.dart';
import 'services/theme_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const AglApp());
}

class AglApp extends StatelessWidget {
  const AglApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SystemMonitor()..start()),
        ChangeNotifierProvider(create: (_) => GpsService()..start()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
        Provider(create: (_) => ApiBenchmark()),
      ],
      child: RepositoryProvider(
        create: (context) => FlatpakRepository(),
        child: BlocProvider(
          create: (context) =>
              FlatpakBloc(repo: context.read<FlatpakRepository>())
                ..add(const RefreshAll()),
          child: Builder(builder: (context) {
            final isDark = context.watch<ThemeService>().isDark;
            return MaterialApp(
              title: 'AGL App Store',
              debugShowCheckedModeBanner: false,
              theme: isDark ? AppTheme.dark() : AppTheme.light(),
              home: const _Shell(),
              builder: (context, child) {
                // Scale UI for small portrait displays (e.g. 7" 1080x1920)
                // The app was designed for landscape; on portrait the logical
                // pixels are too small, making everything tiny.
                final mq = MediaQuery.of(context);
                final isPortrait = mq.size.height > mq.size.width;
                final shortSide = isPortrait ? mq.size.width : mq.size.height;
                // Scale up if short side is narrow (< 600 logical px)
                double scaleFactor = 1.0;
                if (shortSide < 600) {
                  scaleFactor = 1.35;
                } else if (shortSide < 800) {
                  scaleFactor = 1.2;
                }
                if (scaleFactor == 1.0) return child!;
                return MediaQuery(
                  data: mq.copyWith(
                    textScaler: TextScaler.linear(
                        mq.textScaler.scale(scaleFactor)),
                  ),
                  child: Transform.scale(
                    scale: scaleFactor,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: mq.size.width / scaleFactor,
                      height: mq.size.height / scaleFactor,
                      child: child,
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}

// =====================================================================
// SHELL
// =====================================================================
class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  final _scrollCtl = ScrollController();
  final _searchCtl = TextEditingController();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    // Auto-setup remotes + refresh appstream on every launch.
    // Both are fire-and-forget — non-blocking background processes.
    FlatpakPlatform.ensureRemote().then((_) {
      FlatpakPlatform.refreshAppstream().catchError((_) {});
    }).catchError((_) {});
  }

  void _onScroll() {
    if (!mounted) return;
    if (_scrollCtl.position.pixels >=
        _scrollCtl.position.maxScrollExtent - 400) {
      context.read<FlatpakBloc>().add(const LoadNextPage());
    }
  }

  @override
  void dispose() {
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<FlatpakBloc>();
    return Scaffold(
      body: _buildBody(bloc),
      bottomNavigationBar: _bottomNav(bloc),
    );
  }

  static const _navItems = <_NavItem>[
    _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
    _NavItem(Icons.grid_view_outlined, Icons.grid_view_rounded, 'Browse'),
    _NavItem(Icons.download_done_outlined, Icons.download_done_rounded, 'Installed'),
    _NavItem(Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
    _NavItem(Icons.monitor_heart_outlined, Icons.monitor_heart_rounded, 'Monitor'),
  ];

  Widget _bottomNav(FlatpakBloc bloc) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: List.generate(_navItems.length, (i) {
              final item = _navItems[i];
              final active = _tab == i;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final wasHome = _tab == 0;
                    setState(() => _tab = i);
                    if (i == 0 && wasHome) bloc.add(const RefreshAll());
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        active ? item.activeIcon : item.icon,
                        size: 24,
                        color: active ? AppColors.brand : AppColors.textTertiary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? AppColors.brand : AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Glow dot
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: active ? 6 : 0,
                        height: active ? 6 : 0,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? AppColors.brand : Colors.transparent,
                          boxShadow: active
                              ? [BoxShadow(
                                  color: AppColors.brand.withValues(alpha: 0.60),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                )]
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(FlatpakBloc bloc) {
    switch (_tab) {
      case 1: return const CategoriesPage();
      case 2: return const InstalledAppsPage();
      case 3: return const SettingsPage();
      case 4: return const MonitorPage();
      default: return _homePage(bloc);
    }
  }

  Widget _homePage(FlatpakBloc bloc) {
    return SafeArea(
      child: Column(
        children: [
          _homeAppBar(bloc),
          Expanded(child: _homeContent(bloc)),
        ],
      ),
    );
  }

  Widget _homeAppBar(FlatpakBloc bloc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH, AppSpacing.md, AppSpacing.pageH, 0),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.brand, AppColors.accentCyan],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.rMd),
                ),
                child: const Icon(Icons.apps_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AGL Store',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text('Discover apps for your vehicle',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showSearch(context, bloc),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: context.colors.cardEl,
                    borderRadius: BorderRadius.circular(AppSpacing.rMd),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: const Icon(Icons.search_rounded,
                      size: 20, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          BlocBuilder<FlatpakBloc, FlatpakState>(
            buildWhen: (p, c) {
              final ps = p is FlatpakLoaded ? p.source : null;
              final cs = c is FlatpakLoaded ? c.source : null;
              return ps != cs;
            },
            builder: (context, state) {
              final src = state is FlatpakLoaded
                  ? state.source : AppSource.pensHub;
              return _SourceToggle(
                current: src,
                onChanged: (s) => bloc.add(SwitchSource(s)),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _homeContent(FlatpakBloc bloc) {
    return BlocConsumer<FlatpakBloc, FlatpakState>(
      buildWhen: (p, c) {
        if (p.runtimeType != c.runtimeType) return true;
        if (p is FlatpakLoaded && c is FlatpakLoaded) {
          return p.items != c.items || p.hasMore != c.hasMore ||
              p.installed != c.installed || p.installingIds != c.installingIds;
        }
        return true;
      },
      listenWhen: (p, c) => c is FlatpakError,
      listener: (context, state) {
        if (state is FlatpakError) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      builder: (context, state) {
        if (state is FlatpakLoading) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.brand));
        }
        if (state is FlatpakError) {
          return Center(
            child: TextButton.icon(
              onPressed: () => bloc.add(const RefreshAll()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tap to retry'),
            ),
          );
        }
        if (state is FlatpakLoaded) {
          final items = state.items;
          if (items.isEmpty) return const _EmptyState();
          final featured = items.take(4).toList();
          final rest = items.skip(4).toList();

          return CustomScrollView(
            controller: _scrollCtl,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                  child: Row(
                    children: [
                      Container(
                        width: 4, height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: const LinearGradient(
                            colors: [AppColors.brand, AppColors.accentCyan],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text('Featured',
                          style: Theme.of(context).textTheme.headlineMedium),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              SliverToBoxAdapter(
                child: LayoutBuilder(builder: (context, box) {
                  final w = box.maxWidth;
                  // Portrait narrow: smaller cards. Wide: bigger cards.
                  final cardW = w < 400 ? w * 0.75 : w < 600 ? w * 0.65 : 300.0;
                  final cardH = w < 400 ? 180.0 : 220.0;
                  return SizedBox(
                    height: cardH,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                      itemCount: featured.length,
                      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
                      itemBuilder: (_, i) {
                        final pkg = featured[i];
                        return GestureDetector(
                          key: ValueKey('f_${pkg.id}'),
                          onTap: () => _openDetail(context, pkg),
                          child: _FeaturedCard(package: pkg, width: cardW),
                        );
                      },
                    ),
                  );
                }),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageH, AppSpacing.xxxl, AppSpacing.pageH, AppSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        width: 4, height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: const LinearGradient(
                            colors: [AppColors.accentPink, AppColors.accentOrange],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text('All apps',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(width: AppSpacing.sm),
                      Text('${items.length}+',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                sliver: SliverLayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.crossAxisExtent > 700;
                  if (wide) {
                    // 2-column grid for landscape / wide displays
                    return SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisSpacing: AppSpacing.md,
                        mainAxisExtent: 80,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index >= rest.length) return null;
                          return _buildAppTile(context, rest[index], state, bloc);
                        },
                        childCount: rest.length,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: false,
                      ),
                    );
                  }
                  // Single column for portrait / narrow
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= rest.length) {
                          return state.hasMore
                              ? const Padding(
                                  padding: EdgeInsets.all(AppSpacing.xxl),
                                  child: Center(child: CircularProgressIndicator(
                                      color: AppColors.brand)))
                              : const SizedBox(height: AppSpacing.huge);
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _buildAppTile(context, rest[index], state, bloc),
                        );
                      },
                      childCount: rest.length + (state.hasMore ? 1 : 0),
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: false,
                    ),
                  );
                }),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _showSearch(BuildContext context, FlatpakBloc bloc) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.colors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rXl)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Search', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _searchCtl,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'App name...', prefixIcon: Icon(Icons.search_rounded)),
                onSubmitted: (q) {
                  bloc.add(LoadFirstPage(query: q.trim().isEmpty ? null : q));
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppTile(BuildContext context, FlatpakPackage pkg,
      FlatpakLoaded state, FlatpakBloc bloc) {
    return RepaintBoundary(
      key: ValueKey(pkg.id),
      child: _AppTile(
        package: pkg,
        isInstalled: state.installed.contains(pkg.flatpakId),
        isInstalling: state.installingIds.contains(pkg.id),
        onTap: () => _openDetail(context, pkg),
        onInstall: () {
          bloc.add(InstallApp(pkg.flatpakId));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloading ${pkg.name}...')));
        },
        onUninstall: () => bloc.add(UninstallApp(pkg.flatpakId)),
      ),
    );
  }

  void _openDetail(BuildContext context, FlatpakPackage pkg) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => AppDetailPage(package: pkg)));
  }
}

// =====================================================================
// SOURCE TOGGLE
// =====================================================================
class _SourceToggle extends StatelessWidget {
  final AppSource current;
  final ValueChanged<AppSource> onChanged;
  const _SourceToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.cardEl,
        borderRadius: BorderRadius.circular(AppSpacing.rFull),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          for (final s in AppSource.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: current == s ? context.colors.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppSpacing.rFull),
                    boxShadow: current == s
                        ? [BoxShadow(
                            color: (s == AppSource.pensHub
                                    ? AppColors.accentCyan
                                    : AppColors.accentOrange)
                                .withValues(alpha: 0.20),
                            blurRadius: 12,
                            spreadRadius: 0,
                          )]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        s == AppSource.pensHub
                            ? Icons.storefront_rounded
                            : Icons.public_rounded,
                        size: 18,
                        color: current == s
                            ? (s == AppSource.pensHub
                                ? AppColors.accentCyan
                                : AppColors.accentOrange)
                            : AppColors.textTertiary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        s.label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: current == s
                                  ? (s == AppSource.pensHub
                                      ? AppColors.accentCyan
                                      : AppColors.accentOrange)
                                  : AppColors.textTertiary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =====================================================================
// FEATURED CARD
// =====================================================================
class _FeaturedCard extends StatelessWidget {
  final FlatpakPackage package;
  final double width;
  const _FeaturedCard({required this.package, this.width = 300});

  @override
  Widget build(BuildContext context) {
    final grad = AppColors.gradientFor(package.id);
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.rXl),
        gradient: LinearGradient(
          colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -30, right: -30,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -20, left: -15,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          // Bottom gradient overlay for text readability
          Positioned(
            left: 0, right: 0, bottom: 0, height: 100,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(AppSpacing.rXl)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top row: icon + badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(AppSpacing.rMd),
                      ),
                      child: Center(child: _AppIcon(url: package.icon, size: 32)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(AppSpacing.rFull),
                      ),
                      child: const Text('FEATURED',
                          style: TextStyle(
                            color: Colors.white, fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          )),
                    ),
                  ],
                ),
                // Bottom: text
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(package.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(package.summary ?? '',
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13, height: 1.35)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// APP TILE
// =====================================================================
class _AppTile extends StatelessWidget {
  final FlatpakPackage package;
  final bool isInstalled;
  final bool isInstalling;
  final VoidCallback onTap;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  const _AppTile({
    required this.package, required this.isInstalled,
    required this.isInstalling, required this.onTap,
    required this.onInstall, required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final grad = AppColors.gradientFor(package.id);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(AppSpacing.rLg),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            // Gradient accent strip
            Container(
              width: 4,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(AppSpacing.rLg)),
                gradient: LinearGradient(
                  colors: grad,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppSpacing.rMd),
                        gradient: LinearGradient(
                            colors: grad, begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                      ),
                      child: Center(child: _AppIcon(url: package.icon, size: 30)),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(package.name, maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 3),
                          Text(package.summary ?? '', maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _buildAction(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    if (isInstalling) {
      return const SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand));
    }
    if (isInstalled) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onUninstall,
          child: const Icon(Icons.delete_outline_rounded,
              color: AppColors.danger, size: 20),
        ),
      ]);
    }
    return GestureDetector(
      onTap: onInstall,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(AppSpacing.rFull),
        ),
        child: Text('Install',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}

// =====================================================================
// EMPTY STATE
// =====================================================================
class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: const BoxDecoration(
              color: AppColors.brandSoft, shape: BoxShape.circle),
          child: const Icon(Icons.apps_rounded, size: 36, color: AppColors.brand),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('No apps found', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text('Try a different search or pull to refresh.',
            style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }
}

// =====================================================================
// APP ICON
// =====================================================================
class _AppIcon extends StatelessWidget {
  final String? url;
  final double size;
  const _AppIcon({required this.url, required this.size});
  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Icon(Icons.apps_rounded, size: size, color: Colors.white70);
    }
    return CachedNetworkImage(
      imageUrl: url!,
      width: size, height: size,
      memCacheWidth: (size * 2).toInt(),
      fit: BoxFit.contain,
      placeholder: (_, __) =>
          Icon(Icons.apps_rounded, size: size, color: Colors.white38),
      errorWidget: (_, __, ___) =>
          Icon(Icons.broken_image_rounded, size: size, color: Colors.white38),
    );
  }
}
