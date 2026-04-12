import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
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
import 'services/system_monitor.dart';
import 'services/gps_service.dart';
import 'services/api_benchmark.dart';
import 'platform/flatpak_platform.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const FlatpakApp());
}

class FlatpakApp extends StatelessWidget {
  const FlatpakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SystemMonitor()..start()),
        ChangeNotifierProvider(create: (_) => GpsService()..start()),
        Provider(create: (_) => ApiBenchmark()),
      ],
      child: RepositoryProvider(
        create: (context) => FlatpakRepository(),
        child: BlocProvider(
          create: (context) =>
              FlatpakBloc(repo: context.read<FlatpakRepository>())
                ..add(const RefreshAll()),
          child: MaterialApp(
            title: 'AGL App Store',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const FlatpakHomePage(),
          ),
        ),
      ),
    );
  }
}

class FlatpakHomePage extends StatefulWidget {
  const FlatpakHomePage({super.key});

  @override
  State<FlatpakHomePage> createState() => _FlatpakHomePageState();
}

class _FlatpakHomePageState extends State<FlatpakHomePage> {
  final _scrollCtl = ScrollController();
  final _searchCtl = TextEditingController();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    _setupPensHubRemote();
  }

  Future<void> _setupPensHubRemote() async {
    try {
      final result = await FlatpakPlatform.ensureRemote();
      if (result['added'] == true && mounted) {
        // Remote was newly added — reload app list so PensHub apps appear
        if (mounted) context.read<FlatpakBloc>().add(const RefreshAll());
      }
      if (result['error'] != null) {
        debugPrint('[PensHub] Remote setup failed: \${result['error']}');
      }
    } catch (e) {
      debugPrint('[PensHub] ensureRemote error: \$e');
    }
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 72,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.brand, AppColors.accentViolet],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.apps_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AGL App Store',
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Discover & install Linux apps',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_selectedIndex == 0)
            _CircleIconButton(
              icon: Icons.search_rounded,
              onTap: () => _showSearch(context, bloc),
            ),
          const SizedBox(width: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderSubtle, width: 2),
              ),
              child: const CircleAvatar(
                radius: 18,
                backgroundImage: NetworkImage(
                  'https://i.pravatar.cc/150?img=5',
                ),
              ),
            ),
          ),
        ],
        bottom: _selectedIndex == 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(64),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageGutter,
                    0,
                    AppSpacing.pageGutter,
                    AppSpacing.md,
                  ),
                  child: BlocBuilder<FlatpakBloc, FlatpakState>(
                    buildWhen: (prev, curr) {
                      final pSrc =
                          prev is FlatpakLoaded ? prev.source : null;
                      final cSrc =
                          curr is FlatpakLoaded ? curr.source : null;
                      return pSrc != cSrc;
                    },
                    builder: (context, state) {
                      final current = state is FlatpakLoaded
                          ? state.source
                          : AppSource.pensHub;
                      return _SourceToggle(
                        current: current,
                        onChanged: (s) =>
                            context.read<FlatpakBloc>().add(SwitchSource(s)),
                      );
                    },
                  ),
                ),
              )
            : null,
      ),
      body: _buildBody(bloc),
      bottomNavigationBar: _buildBottomNav(bloc),
    );
  }

  void _showSearch(BuildContext context, FlatpakBloc bloc) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search apps',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _searchCtl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'App name…',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (q) {
                  bloc.add(
                    LoadFirstPage(query: q.trim().isEmpty ? null : q),
                  );
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav(FlatpakBloc bloc) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            final wasHome = _selectedIndex == 0;
            setState(() => _selectedIndex = index);
            if (index == 0 && wasHome) {
              bloc.add(const RefreshAll());
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_outlined),
              activeIcon: Icon(Icons.grid_view_rounded),
              label: 'Categories',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.download_done_outlined),
              activeIcon: Icon(Icons.download_done_rounded),
              label: 'Installed',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.monitor_heart_outlined),
              activeIcon: Icon(Icons.monitor_heart_rounded),
              label: 'Monitor',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(FlatpakBloc bloc) {
    switch (_selectedIndex) {
      case 1:
        return const CategoriesPage();
      case 2:
        return const InstalledAppsPage();
      case 3:
        return const SettingsPage();
      case 4:
        return const MonitorPage();
      default:
        return BlocConsumer<FlatpakBloc, FlatpakState>(
          buildWhen: (prev, curr) {
            if (prev.runtimeType != curr.runtimeType) return true;
            if (prev is FlatpakLoaded && curr is FlatpakLoaded) {
              return prev.items != curr.items ||
                  prev.hasMore != curr.hasMore ||
                  prev.installed != curr.installed ||
                  prev.installingIds != curr.installingIds;
            }
            return true;
          },
          listenWhen: (prev, curr) => curr is FlatpakError,
          listener: (context, state) {
            if (state is FlatpakError) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(state.message)));
            }
          },
          builder: (context, state) {
            if (state is FlatpakLoading) {
              return const Center(child: CircularProgressIndicator());
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
              if (items.isEmpty) {
                return const _EmptyState(
                  icon: Icons.apps_rounded,
                  title: 'No apps found',
                  subtitle: 'Try a different search or pull to refresh.',
                );
              }

              final featuredItems = items.take(3).toList();
              final listItems = items.skip(3).toList();

              return CustomScrollView(
                controller: _scrollCtl,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageGutter,
                        AppSpacing.lg,
                        AppSpacing.pageGutter,
                        AppSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(
                            title: 'Featured',
                            subtitle: 'Editor picks for this week',
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            height: 240,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: featuredItems.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: AppSpacing.lg),
                              itemBuilder: (context, i) {
                                final pkg = featuredItems[i];
                                return GestureDetector(
                                  key: ValueKey('featured_${pkg.id}'),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            AppDetailPage(package: pkg),
                                      ),
                                    );
                                  },
                                  child: FeaturedCard(package: pkg),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxxl),
                          _SectionHeader(
                            title: 'All apps',
                            subtitle: '${items.length}+ available',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= listItems.length) {
                          return state.hasMore
                              ? const Padding(
                                  padding: EdgeInsets.all(AppSpacing.xxl),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : const SizedBox(height: AppSpacing.huge);
                        }
                        final pkg = listItems[index];
                        final installed =
                            state.installed.contains(pkg.flatpakId);
                        final isInstalling =
                            state.installingIds.contains(pkg.id);

                        return RepaintBoundary(
                          key: ValueKey(pkg.id),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.pageGutter,
                              AppSpacing.sm,
                              AppSpacing.pageGutter,
                              AppSpacing.sm,
                            ),
                            child: AppListItem(
                              package: pkg,
                              isInstalled: installed,
                              isInstalling: isInstalling,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AppDetailPage(package: pkg),
                                  ),
                                );
                              },
                              onInstall: () {
                                if (!installed && !isInstalling) {
                                  bloc.add(InstallApp(pkg.flatpakId));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('Downloading ${pkg.name}…'),
                                    ),
                                  );
                                }
                              },
                              onUninstall: () =>
                                  bloc.add(UninstallApp(pkg.flatpakId)),
                            ),
                          ),
                        );
                      },
                      childCount: listItems.length + (state.hasMore ? 1 : 0),
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: false,
                    ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        );
    }
  }
}

// =====================================================================
// SHARED WIDGETS
// =====================================================================

/// Pill segmented control that switches the catalog source between
/// PensHub (cyan) and Flathub (orange). The selected pill animates the
/// indicator and tints icon + label with the source's accent color.
class _SourceToggle extends StatelessWidget {
  final AppSource current;
  final ValueChanged<AppSource> onChanged;
  const _SourceToggle({required this.current, required this.onChanged});

  static const _pensHubAccent = Color(0xFF00D4FF);
  static const _flathubAccent = Color(0xFFFF6B35);

  Color _accentFor(AppSource s) =>
      s == AppSource.pensHub ? _pensHubAccent : _flathubAccent;

  IconData _iconFor(AppSource s) => s == AppSource.pensHub
      ? Icons.storefront_rounded
      : Icons.public_rounded;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          for (final s in AppSource.values)
            Expanded(
              child: _SourceToggleTab(
                source: s,
                icon: _iconFor(s),
                accent: _accentFor(s),
                selected: current == s,
                onTap: () => onChanged(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceToggleTab extends StatelessWidget {
  final AppSource source;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  const _SourceToggleTab({
    required this.source,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? AppColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.20),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? accent : AppColors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  source.label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected ? accent : AppColors.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  // ignore: unused_element_parameter
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.brand),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// FEATURED CARD
// =====================================================================
class FeaturedCard extends StatelessWidget {
  final FlatpakPackage package;

  const FeaturedCard({super.key, required this.package});

  @override
  Widget build(BuildContext context) {
    final gradient = AppColors.gradientFor(package.id);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // decorative ring
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: const Text(
                    'FEATURED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                  child: AppIcon(url: package.icon, size: 56),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      package.summary ?? 'No description available',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
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
// APP LIST ITEM (horizontal card)
// =====================================================================
class AppListItem extends StatelessWidget {
  final FlatpakPackage package;
  final bool isInstalled;
  final bool isInstalling;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;
  final VoidCallback onTap;

  const AppListItem({
    super.key,
    required this.package,
    required this.isInstalled,
    required this.isInstalling,
    required this.onInstall,
    required this.onUninstall,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = AppColors.gradientFor(package.id);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(child: AppIcon(url: package.icon, size: 36)),
              ),
              const SizedBox(width: AppSpacing.lg),

              // Title + summary
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      package.summary ?? 'No description available',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Action button
              _ActionButton(
                isInstalled: isInstalled,
                isInstalling: isInstalling,
                onInstall: onInstall,
                onUninstall: onUninstall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final bool isInstalled;
  final bool isInstalling;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;
  const _ActionButton({
    required this.isInstalled,
    required this.isInstalling,
    required this.onInstall,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    if (isInstalling) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.brandSoft,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Installing',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.brand,
                  ),
            ),
          ],
        ),
      );
    }
    if (isInstalled) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  'Installed',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onUninstall,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.danger,
            tooltip: 'Uninstall',
          ),
        ],
      );
    }
    return ElevatedButton(
      onPressed: onInstall,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
      ),
      child: const Text('Install'),
    );
  }
}

// =====================================================================
// APP ICON
// =====================================================================
class AppIcon extends StatelessWidget {
  final String? url;
  final double size;
  const AppIcon({super.key, required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Icon(Icons.apps_rounded, size: size, color: Colors.white);
    }
    return CachedNetworkImage(
      imageUrl: url!,
      width: size,
      height: size,
      memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).toInt(),
      fit: BoxFit.contain,
      placeholder: (_, __) =>
          Icon(Icons.apps_rounded, size: size, color: Colors.white54),
      errorWidget: (_, __, ___) =>
          Icon(Icons.broken_image_rounded, size: size, color: Colors.white),
    );
  }
}
