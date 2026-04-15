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
import 'services/log_service.dart';
import 'services/system_monitor.dart';
import 'services/gps_service.dart';
import 'services/api_benchmark.dart';
import 'services/theme_service.dart';
import 'services/user_log.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';
import 'theme/app_theme.dart';
import 'widgets/operations_island.dart';
import 'widgets/pressable.dart';
import 'widgets/skeleton.dart';

void main() {
  LogService.install();
  LogService.runZoned(() {
    // Initialise the binding inside the zone so async errors surfaced
    // by Flutter's machinery propagate to runZonedGuarded's onError
    // (per the Flutter cookbook's error-handling guidance).
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const AglApp());
  });
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
                // Boost text size for hard-to-read displays without rescaling
                // the whole layout (Transform.scale breaks LayoutBuilder /
                // MediaQuery propagation and causes overflow). Text-only
                // scaling lets the existing responsive layouts adapt.
                final mq = MediaQuery.of(context);
                final isPortrait = mq.size.height > mq.size.width;
                final shortSide = isPortrait ? mq.size.width : mq.size.height;
                final longSide = isPortrait ? mq.size.height : mq.size.width;
                double textScale = 1.0;
                if (shortSide < 600) {
                  textScale = 1.15;
                } else if (mq.devicePixelRatio < 1.5 && longSide >= 1600) {
                  // 7" 1920×1080 reporting DPR=1.0 — bump text only.
                  textScale = 1.25;
                }
                if (textScale == 1.0) return child!;
                return MediaQuery(
                  data: mq.copyWith(
                    textScaler:
                        TextScaler.linear(mq.textScaler.scale(textScale)),
                  ),
                  child: child!,
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
    // Remote reconciliation is Flathub-first, then PensHub with GPG
    // self-heal; see FlatpakPlatform.ensureRemotes for the policy.
    FlatpakPlatform.ensureRemotes().then((result) {
      debugPrint('[FLATPAK] ensureRemotes result=$result');
      FlatpakPlatform.refreshAppstream().catchError((_) {});
    }).catchError((e) {
      debugPrint('[FLATPAK] ensureRemotes threw: $e');
    });
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
      body: Stack(
        children: [
          // Page body
          Positioned.fill(child: _buildBody(bloc)),
          // Floating operations dynamic island (top-center)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OperationsIsland(),
          ),
        ],
      ),
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
    // Vehicle-friendly bottom nav: oversized touch targets (≥64dp tall),
    // larger icons (28) and labels (13), prominent active-state pill so
    // the driver can confirm location with a single glance.
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
          child: Row(
            children: List.generate(_navItems.length, (i) {
              final item = _navItems[i];
              final active = _tab == i;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final wasHome = _tab == 0;
                    UserLog.tap('nav.tab',
                        {'to': item.label, 'index': i, 'from': _tab});
                    setState(() => _tab = i);
                    if (i == 0 && wasHome) {
                      UserLog.tap('nav.tab.refresh-home');
                      bloc.add(const RefreshAll());
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm),
                    constraints: const BoxConstraints(minHeight: 64),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.brand.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSpacing.rLg),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          active ? item.activeIcon : item.icon,
                          size: 28,
                          color: active
                              ? AppColors.brand
                              : context.colors.textS,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: active
                                ? AppColors.brand
                                : context.colors.textS,
                          ),
                        ),
                      ],
                    ),
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
                  color: context.colors.cardEl,
                  border: Border.all(color: context.colors.border),
                  borderRadius: BorderRadius.circular(AppSpacing.rMd),
                ),
                child: Icon(Icons.apps_rounded,
                    color: context.colors.textP, size: 22),
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
              Pressable(
                onTap: () {
                  UserLog.tap('header.search-open');
                  _showSearch(context, bloc);
                },
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: context.colors.cardEl,
                    borderRadius: BorderRadius.circular(AppSpacing.rMd),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_rounded,
                          size: 20, color: AppColors.textPrimary),
                      const SizedBox(width: 6),
                      Text(
                        'Search',
                        style: TextStyle(
                          color: context.colors.textP,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Close App — vehicle-friendly: door-exit icon + label
              Pressable(
                onTap: () {
                  UserLog.tap('header.exit-open');
                  _confirmExit(context);
                },
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.rMd),
                    border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.exit_to_app_rounded,
                          size: 22, color: AppColors.danger),
                      SizedBox(width: 6),
                      Text(
                        'Close App',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
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
          // Install-state fields (installingIds, installProgress,
          // installPhase) are consumed per-tile via BlocSelector in
          // `_buildAppTile`, so we intentionally omit them here. That
          // stops a 200ms progress tick from tearing down the entire
          // CustomScrollView (featured row + up to 300 list tiles).
          // `installed` stays because the installed-count header and
          // other coarse widgets depend on it.
          return p.items != c.items ||
              p.hasMore != c.hasMore ||
              p.installed != c.installed ||
              p.isLoading != c.isLoading;
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
          return const _SkeletonHomeContent();
        }
        if (state is FlatpakError) {
          return Center(
            child: TextButton.icon(
              onPressed: () {
                UserLog.tap('home.error.retry');
                bloc.add(const RefreshAll());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tap to retry'),
            ),
          );
        }
        if (state is FlatpakLoaded) {
          // Source-switch in flight: show skeletons over the whole
          // feed while the new catalog's items load, paired with the
          // dynamic island's "Switching to X" pill at the top.
          if (state.isLoading) {
            return const _SkeletonHomeContent();
          }
          final items = state.items;
          if (items.isEmpty) return const _EmptyState();
          final featured = items.take(4).toList();
          final rest = items.skip(4).toList();

          return RefreshIndicator(
            color: AppColors.brand,
            backgroundColor: context.colors.card,
            edgeOffset: 8,
            displacement: 40,
            onRefresh: () async {
              bloc.add(const RefreshAll());
              // Wait for the next FlatpakLoaded after the refresh completes.
              await bloc.stream
                  .where((s) => s is FlatpakLoaded && !s.isLoading)
                  .first
                  .timeout(const Duration(seconds: 15), onTimeout: () => state);
            },
            child: CustomScrollView(
            controller: _scrollCtl,
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                  child: _SectionHeader(label: 'FEATURED'),
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
                        return FadeInSlide(
                          key: ValueKey('f_${pkg.id}'),
                          delay: Duration(milliseconds: 40 * i),
                          child: Pressable(
                            onTap: () {
                              UserLog.tap('home.featured.open',
                                  {'id': pkg.flatpakId, 'slot': i});
                              _openDetail(context, pkg);
                            },
                            child: _FeaturedCard(package: pkg, width: cardW),
                          ),
                        );
                      },
                    ),
                  );
                }),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.pageH,
                      AppSpacing.xxxl, AppSpacing.pageH, AppSpacing.md),
                  child: _SectionHeader(
                    label: 'ALL APPS',
                    trailing: '${items.length}',
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
                        mainAxisExtent: 96,
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
                        // Staggered entrance, capped at the first
                        // screenful so deep-scroll doesn't have to wait.
                        final staggerMs = index < 12 ? 25 * index : 0;
                        return FadeInSlide(
                          delay: Duration(milliseconds: staggerMs),
                          child: Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: _buildAppTile(
                                context, rest[index], state, bloc),
                          ),
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
            ),
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
                  final clean = q.trim();
                  UserLog.tap('home.search.submit',
                      {'query': clean.isEmpty ? '(cleared)' : clean});
                  bloc.add(LoadFirstPage(query: clean.isEmpty ? null : clean));
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
    // The bloc keys installingIds/installed off the *normalized*
    // flatpakId. For Flathub apps `pkg.id` is the slug, which does not
    // match — always normalize from `pkg.flatpakId` before lookup,
    // otherwise the spinner/installed state never appears on the tile.
    final id = FlatpakRepository.normalizeFlatpakId(pkg.flatpakId);
    return RepaintBoundary(
      key: ValueKey(pkg.id),
      // Per-tile selector so only this tile rebuilds when its own
      // install state changes. The selector's equality collapses to
      // (isInstalled, isInstalling, progress) scoped to this id, so
      // a progress tick for app X doesn't touch tile Y.
      child: BlocSelector<FlatpakBloc, FlatpakState, _TileInstall>(
        selector: (s) => s is FlatpakLoaded
            ? _TileInstall(
                installed: s.installed.contains(id),
                installing: s.installingIds.contains(id),
                progress: s.installProgress[id],
              )
            : const _TileInstall(),
        builder: (_, t) => _AppTile(
          package: pkg,
          isInstalled: t.installed,
          isInstalling: t.installing,
          installProgress: t.progress,
          onTap: () {
            UserLog.tap('home.tile.open', {'id': pkg.flatpakId});
            _openDetail(context, pkg);
          },
          onInstall: () {
            UserLog.tap('home.tile.install', {'id': pkg.flatpakId});
            bloc.add(InstallApp(pkg.flatpakId));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Downloading ${pkg.name}...')));
          },
          onUninstall: () {
            UserLog.tap('home.tile.uninstall', {'id': pkg.flatpakId});
            bloc.add(UninstallApp(pkg.flatpakId));
          },
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, FlatpakPackage pkg) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => AppDetailPage(package: pkg)));
  }

  /// Shows a confirmation dialog then exits the app (kills flutter-auto).
  /// Useful on embedded targets where the app runs in kiosk mode and
  /// otherwise requires SSH + `systemctl stop` to kill.
  void _confirmExit(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rLg)),
        title: const Text('Close App Store?'),
        content: const Text(
            'This will stop the AGL App Store service and return to the '
            'compositor. Re-open it from the home launcher.'),
        actions: [
          TextButton(
            onPressed: () {
              UserLog.tap('exit.cancel');
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              UserLog.tap('exit.confirm');
              Navigator.pop(ctx);
              FlatpakPlatform.exitApp();
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// SOURCE TOGGLE — Tesla-style segmented control: squared-off corners,
// monochrome active state, no accent glow.
// =====================================================================
class _SourceToggle extends StatelessWidget {
  final AppSource current;
  final ValueChanged<AppSource> onChanged;
  const _SourceToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.colors.cardEl,
        borderRadius: BorderRadius.circular(AppSpacing.rMd),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          for (final s in AppSource.values)
            Expanded(
              child: Pressable(
                onTap: () {
                  UserLog.tap('source.switch',
                      {'to': s.label, 'from': current.label});
                  onChanged(s);
                },
                pressedScale: 0.96,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: current == s
                        ? context.colors.card
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppSpacing.rSm),
                    border: current == s
                        ? Border.all(color: context.colors.border)
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        s == AppSource.pensHub
                            ? Icons.storefront_rounded
                            : Icons.public_rounded,
                        size: 17,
                        color: current == s
                            ? context.colors.textP
                            : context.colors.textT,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        s.label,
                        style: TextStyle(
                          color: current == s
                              ? context.colors.textP
                              : context.colors.textT,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
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
// SECTION HEADER — Tesla-style: small uppercase label, generous
// letter-spacing, hairline rule, optional trailing count. Replaces the
// colorful gradient accent bars.
// =====================================================================
class _SectionHeader extends StatelessWidget {
  final String label;
  final String? trailing;
  const _SectionHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.colors.textP,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Container(
            height: 1,
            color: context.colors.border,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            trailing!,
            style: TextStyle(
              color: context.colors.textT,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );
  }
}

// =====================================================================
// FEATURED CARD — Tesla-style: flat surface, hairline border, one
// subtle tint strip, no rainbow gradient.
// =====================================================================
class _FeaturedCard extends StatelessWidget {
  final FlatpakPackage package;
  final double width;
  const _FeaturedCard({required this.package, this.width = 300});

  @override
  Widget build(BuildContext context) {
    // Single accent color per card instead of full-card gradient — use
    // the first color of the deterministic package gradient so every
    // card still has its own identity, applied only as a thin top bar.
    final accent = AppColors.gradientFor(package.id).first;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppSpacing.rLg),
        border: Border.all(color: context.colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thin accent bar — the only color on the card
          Container(height: 3, color: accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top row: icon + FEATURED tag
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Hero(
                        tag: 'app-icon-${package.flatpakId}',
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: context.colors.cardEl,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.rMd),
                            border: Border.all(color: context.colors.border),
                          ),
                          child: Center(
                            child: _AppIcon(url: package.icon, size: 32),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'FEATURED',
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                  // Bottom: text
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        package.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textP,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        package.summary ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textS,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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

/// Minimal value type for the per-tile BlocSelector — identity-compared
/// on three tile-local fields so neighboring tiles' progress ticks don't
/// cause this tile to rebuild.
@immutable
class _TileInstall {
  final bool installed;
  final bool installing;
  final int? progress;
  const _TileInstall({
    this.installed = false,
    this.installing = false,
    this.progress,
  });

  @override
  bool operator ==(Object other) =>
      other is _TileInstall &&
      other.installed == installed &&
      other.installing == installing &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(installed, installing, progress);
}

class _AppTile extends StatelessWidget {
  final FlatpakPackage package;
  final bool isInstalled;
  final bool isInstalling;
  final int? installProgress;
  final VoidCallback onTap;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  const _AppTile({
    required this.package, required this.isInstalled,
    required this.isInstalling, this.installProgress,
    required this.onTap, required this.onInstall,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(AppSpacing.rLg),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            // Monochrome icon tile — shared-element flight to detail.
            Hero(
              tag: 'app-icon-${package.flatpakId}',
              flightShuttleBuilder: _iconFlight,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: context.colors.cardEl,
                  borderRadius: BorderRadius.circular(AppSpacing.rMd),
                  border: Border.all(color: context.colors.border),
                ),
                child: Center(
                  child: _AppIcon(url: package.icon, size: 30),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    package.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    package.summary ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Smooth morph between Install / Installing / Installed
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1.0).animate(anim),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_actionKey()),
                child: _buildAction(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _actionKey() {
    if (isInstalling) return 'ing-${installProgress ?? -1}';
    if (isInstalled) return 'ed';
    return 'idle';
  }

  /// Preserve the icon's square shape + border during the shared-element
  /// transition so it doesn't morph into a circle mid-flight.
  static Widget _iconFlight(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final Hero toHero = toHeroContext.widget as Hero;
    return Material(
      color: Colors.transparent,
      child: toHero.child,
    );
  }

  Widget _buildAction(BuildContext context) {
    if (isInstalling) {
      // Show a downloading pill: progress ring + percent if available,
      // otherwise indeterminate spinner. Replaces the previous bare
      // spinner so the user can see install is actually progressing.
      final pct = installProgress;
      final hasPct = pct != null && pct > 0;
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.brand.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppSpacing.rFull),
          border: Border.all(
              color: AppColors.brand.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: hasPct ? pct / 100 : null,
                strokeWidth: 2,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.brand),
                backgroundColor:
                    AppColors.brand.withValues(alpha: 0.18),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              hasPct ? '$pct%' : 'Installing',
              style: const TextStyle(
                color: AppColors.brand,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    if (isInstalled) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded,
            color: AppColors.success, size: 20),
        const SizedBox(width: 4),
        Pressable(
          onTap: onUninstall,
          pressedScale: 0.85,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.delete_outline_rounded,
                color: AppColors.danger, size: 20),
          ),
        ),
      ]);
    }
    final size = package.formattedDownloadSize;
    return Pressable(
      onTap: onInstall,
      pressedScale: 0.94,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(AppSpacing.rFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Install',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            if (size != null) ...[
              const SizedBox(width: 6),
              Container(
                width: 3, height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(size,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ],
        ),
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
      fadeInDuration: const Duration(milliseconds: 220),
      fadeOutDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) =>
          Icon(Icons.apps_rounded, size: size, color: Colors.white38),
      errorWidget: (_, __, ___) =>
          Icon(Icons.broken_image_rounded, size: size, color: Colors.white38),
    );
  }
}

// =====================================================================
// SKELETON HOME CONTENT
// =====================================================================
/// Skeleton layout shown while the home feed is loading or a source
/// switch is in flight. Mirrors the real feed's shape (Featured row +
/// All apps list) so the layout doesn't jump when real content arrives.
class _SkeletonHomeContent extends StatelessWidget {
  const _SkeletonHomeContent();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final cardW = w < 400
          ? w * 0.75
          : w < 600
              ? w * 0.65
              : 300.0;
      final cardH = w < 400 ? 180.0 : 220.0;
      final wide = w > 700;

      return CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          // Section heading placeholder
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageH),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: context.colors.cardEl,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const SkeletonBox(width: 130, height: 22),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

          // Featured row skeleton
          SliverToBoxAdapter(
            child: SizedBox(
              height: cardH,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageH),
                itemCount: 4,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.lg),
                itemBuilder: (_, __) =>
                    SkeletonFeaturedCard(width: cardW, height: cardH),
              ),
            ),
          ),

          // "All apps" heading placeholder
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.pageH,
                  AppSpacing.xxxl, AppSpacing.pageH, AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: context.colors.cardEl,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const SkeletonBox(width: 110, height: 22),
                ],
              ),
            ),
          ),

          // All apps tiles
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
            sliver: wide
                ? SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: AppSpacing.md,
                      mainAxisExtent: 80,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, __) => const SkeletonAppTile(),
                      childCount: 6,
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, __) => const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.md),
                        child: SkeletonAppTile(),
                      ),
                      childCount: 6,
                    ),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.huge)),
        ],
      );
    });
  }
}
