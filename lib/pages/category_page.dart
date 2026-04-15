import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/flatpak_bloc.dart';
import '../data/flatpak_repository.dart';
import '../models/app_source.dart';
import '../models/flatpak_package.dart';
import '../services/user_log.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/pressable.dart';
import 'app_detail_page.dart';

/// Browse-by-category page.
///
/// PensHub and Flathub expose different category sets via different APIs:
///   - PensHub:  GET /apps?category=NAME — backend `seed_apps.py:35-48`
///                (12 categories incl. Settings, Accessibility)
///   - Flathub:  GET /collection/category/NAME — flathub.org/api/v2
///                (12 freedesktop main + Audio/Video subcategories)
///
/// The card grid switches automatically when the source toggle changes.
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  // ── PensHub catalog (12 categories from backend) ────────────────────
  static const _pensHubCats = <_Cat>[
    _Cat('Music & Video', 'AudioVideo', Icons.headphones_rounded,
        [Color(0xFFFF6B9D), Color(0xFFFF9F43)], 'Players & streaming'),
    _Cat('Developer', 'Development', Icons.code_rounded,
        [Color(0xFF00B4D8), Color(0xFF6C5CE7)], 'Tools & SDKs'),
    _Cat('Games', 'Game', Icons.sports_esports_rounded,
        [Color(0xFFA29BFE), Color(0xFFFF6B9D)], 'Play on the go'),
    _Cat('Graphics', 'Graphics', Icons.brush_rounded,
        [Color(0xFF00C853), Color(0xFF00B4D8)], 'Photos & design'),
    _Cat('Network', 'Network', Icons.wifi_rounded,
        [Color(0xFF00B4D8), Color(0xFF00E676)], 'Browse & connect'),
    _Cat('Productivity', 'Office', Icons.work_rounded,
        [Color(0xFF00D4FF), Color(0xFF00E676)], 'Office & planning'),
    _Cat('Learning', 'Education', Icons.school_rounded,
        [Color(0xFFFF9F43), Color(0xFFFF6B9D)], 'Courses & ref'),
    _Cat('Science', 'Science', Icons.science_rounded,
        [Color(0xFF00E676), Color(0xFF00D4FF)], 'Research & calc'),
    _Cat('System', 'System', Icons.memory_rounded,
        [Color(0xFF6C5CE7), Color(0xFFA29BFE)], 'Power & monitor'),
    _Cat('Utilities', 'Utility', Icons.layers_rounded,
        [Color(0xFF6C5CE7), Color(0xFFFF6B9D)], 'Handy helpers'),
    _Cat('Settings', 'Settings', Icons.tune_rounded,
        [Color(0xFF8B5CF6), Color(0xFF00B4D8)], 'Configure your device'),
    _Cat('Accessibility', 'Accessibility', Icons.accessibility_new_rounded,
        [Color(0xFF00C853), Color(0xFF6C5CE7)], 'Inclusive tools'),
  ];

  // ── Flathub catalog (freedesktop main categories) ───────────────────
  static const _flathubCats = <_Cat>[
    _Cat('Music & Video', 'AudioVideo', Icons.movie_creation_rounded,
        [Color(0xFFE040FB), Color(0xFF7C4DFF)], 'Mixed media apps'),
    _Cat('Audio', 'Audio', Icons.music_note_rounded,
        [Color(0xFFFF6B9D), Color(0xFFFF9F43)], 'Players & editors'),
    _Cat('Video', 'Video', Icons.videocam_rounded,
        [Color(0xFF7C4DFF), Color(0xFF00B4D8)], 'Watch & edit'),
    _Cat('Developer', 'Development', Icons.code_rounded,
        [Color(0xFF00B4D8), Color(0xFF6C5CE7)], 'IDEs & tools'),
    _Cat('Learning', 'Education', Icons.school_rounded,
        [Color(0xFFFF9F43), Color(0xFFFF6B9D)], 'Courses & ref'),
    _Cat('Games', 'Game', Icons.sports_esports_rounded,
        [Color(0xFFA29BFE), Color(0xFFFF6B9D)], 'Action & arcade'),
    _Cat('Graphics', 'Graphics', Icons.brush_rounded,
        [Color(0xFF00C853), Color(0xFF00B4D8)], 'Art & design'),
    _Cat('Network', 'Network', Icons.public_rounded,
        [Color(0xFF00B4D8), Color(0xFF00E676)], 'Web & chat'),
    _Cat('Productivity', 'Office', Icons.work_rounded,
        [Color(0xFF00D4FF), Color(0xFF00E676)], 'Docs & email'),
    _Cat('Science', 'Science', Icons.science_rounded,
        [Color(0xFF00E676), Color(0xFF00D4FF)], 'Research & math'),
    _Cat('System', 'System', Icons.memory_rounded,
        [Color(0xFF6C5CE7), Color(0xFFA29BFE)], 'OS & monitoring'),
    _Cat('Utilities', 'Utility', Icons.layers_rounded,
        [Color(0xFF6C5CE7), Color(0xFFFF6B9D)], 'Handy helpers'),
  ];

  static List<_Cat> _catsFor(AppSource source) => switch (source) {
        AppSource.pensHub => _pensHubCats,
        AppSource.flathub => _flathubCats,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageH, AppSpacing.lg, AppSpacing.pageH, 0),
          child: BlocBuilder<FlatpakBloc, FlatpakState>(
            buildWhen: (p, c) {
              final ps = p is FlatpakLoaded ? p.source : null;
              final cs = c is FlatpakLoaded ? c.source : null;
              return ps != cs;
            },
            builder: (context, state) {
              final source = state is FlatpakLoaded
                  ? state.source
                  : context.read<FlatpakRepository>().currentSource;
              final cats = _catsFor(source);
              return LayoutBuilder(builder: (context, box) {
                final cols =
                    box.maxWidth > 700 ? 3 : box.maxWidth > 380 ? 2 : 1;
                return CustomScrollView(
                  key: ValueKey(source),
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Browse',
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              Text('Categories on ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium),
                              _SourceChip(source: source),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                        ],
                      ),
                    ),
                    SliverGrid(
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisSpacing: AppSpacing.md,
                        childAspectRatio: 1.0,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) =>
                            _CatCard(cat: cats[i], source: source),
                        childCount: cats.length,
                      ),
                    ),
                    const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.huge)),
                  ],
                );
              });
            },
          ),
        ),
      ),
    );
  }
}

class _Cat {
  final String ui;
  final String api;
  final IconData icon;
  final List<Color> grad;
  final String sub;
  const _Cat(this.ui, this.api, this.icon, this.grad, this.sub);
}

// ─── Source pill shown next to the page subtitle ─────────────────────
class _SourceChip extends StatelessWidget {
  final AppSource source;
  const _SourceChip({required this.source});

  @override
  Widget build(BuildContext context) {
    final tint = source == AppSource.pensHub
        ? AppColors.accentCyan
        : AppColors.accentOrange;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            source == AppSource.pensHub
                ? Icons.storefront_rounded
                : Icons.public_rounded,
            size: 13,
            color: tint,
          ),
          const SizedBox(width: 4),
          Text(
            source.label,
            style: TextStyle(
              color: tint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CatCard extends StatelessWidget {
  final _Cat cat;
  final AppSource source;
  const _CatCard({required this.cat, required this.source});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () {
        UserLog.tap('category.open',
            {'name': cat.ui, 'api': cat.api, 'source': source.label});
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _ResultsPage(
              ui: cat.ui,
              api: cat.api,
              source: source,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.rXl),
          gradient: LinearGradient(
            colors: cat.grad,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
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
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(AppSpacing.rSm),
                    ),
                    child: Icon(cat.icon, color: Colors.white, size: 24),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cat.ui,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(cat.sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.70),
                              fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsPage extends StatelessWidget {
  final String ui;
  final String api;
  final AppSource source;
  const _ResultsPage({
    required this.ui,
    required this.api,
    required this.source,
  });

  @override
  Widget build(BuildContext context) {
    final repo = context.read<FlatpakRepository>();
    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(ui, style: const TextStyle(fontSize: 18)),
            Text(
              'on ${source.label}',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.textT,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<FlatpakPackage>>(
        stream: repo.fetchByCategory(api),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.brand));
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final apps = snap.data ?? [];
          if (apps.isEmpty) {
            return snap.connectionState == ConnectionState.done
                ? Center(
                    child: Text('No apps in this category',
                        style: Theme.of(context).textTheme.bodyMedium))
                : const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.brand));
          }
          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.pageH),
            itemCount: apps.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) {
              final app = apps[i];
              final grad = AppColors.gradientFor(app.id);
              return RepaintBoundary(
                key: ValueKey(app.id),
                child: Pressable(
                  onTap: () {
                    UserLog.tap('category.result.open',
                        {'id': app.flatpakId});
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AppDetailPage(package: app)));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(AppSpacing.rLg),
                      border: Border.all(color: context.colors.border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.rSm),
                          gradient: LinearGradient(colors: grad),
                        ),
                        child: Center(
                          child: app.icon != null
                              ? CachedNetworkImage(
                                  imageUrl: app.icon!,
                                  width: 28,
                                  height: 28,
                                  memCacheWidth: 56,
                                  memCacheHeight: 56,
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) => const Icon(
                                      Icons.apps_rounded,
                                      color: Colors.white),
                                  errorWidget: (_, __, ___) => const Icon(
                                      Icons.apps_rounded,
                                      color: Colors.white))
                              : const Icon(Icons.apps_rounded,
                                  color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(app.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium),
                          const SizedBox(height: 2),
                          Text(app.summary ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall),
                        ],
                      )),
                      Icon(Icons.chevron_right_rounded,
                          color: context.colors.textT),
                    ]),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
