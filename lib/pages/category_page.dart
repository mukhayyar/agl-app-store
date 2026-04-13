import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/flatpak_repository.dart';
import '../models/flatpak_package.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_detail_page.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  static const _cats = <_Cat>[
    _Cat('Navigation', 'Science', Icons.map_rounded,
        [Color(0xFF00E676), Color(0xFF00D4FF)], 'Maps & GPS'),
    _Cat('Music', 'AudioVideo', Icons.headphones_rounded,
        [Color(0xFFFF6B9D), Color(0xFFFF9F43)], 'Players & streaming'),
    _Cat('Tools', 'Development', Icons.build_rounded,
        [Color(0xFFFF9F43), Color(0xFFFF5252)], 'Dev & system tools'),
    _Cat('Games', 'Game', Icons.sports_esports_rounded,
        [Color(0xFFA29BFE), Color(0xFFFF6B9D)], 'Play on the go'),
    _Cat('Productivity', 'Office', Icons.calendar_today_rounded,
        [Color(0xFF00D4FF), Color(0xFF00E676)], 'Office & planning'),
    _Cat('Utilities', 'Utility', Icons.layers_rounded,
        [Color(0xFF6C5CE7), Color(0xFFA29BFE)], 'Handy helpers'),
    _Cat('Entertainment', 'AudioVideo', Icons.movie_creation_rounded,
        [Color(0xFFE040FB), Color(0xFF7C4DFF)], 'Movies & media'),
    _Cat('Communication', 'Network', Icons.chat_bubble_rounded,
        [Color(0xFFFF9F43), Color(0xFFFF6B9D)], 'Chat & connect'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageH, AppSpacing.lg, AppSpacing.pageH, 0),
          child: LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth > 700 ? 3 : box.maxWidth > 380 ? 2 : 1;
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Browse',
                          style: Theme.of(context).textTheme.displaySmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Find apps by category',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ),
                ),
                SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: 1.0,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _CatCard(cat: _cats[i]),
                    childCount: _cats.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.huge)),
              ],
            );
          }),
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

class _CatCard extends StatelessWidget {
  final _Cat cat;
  const _CatCard({required this.cat});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => _ResultsPage(ui: cat.ui, api: cat.api))),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.rXl),
          gradient: LinearGradient(
            colors: cat.grad,
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20, top: -20,
              child: Container(
                width: 90, height: 90,
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
                      Text(cat.ui, style: const TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(cat.sub, style: TextStyle(
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
  const _ResultsPage({required this.ui, required this.api});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<FlatpakRepository>();
    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(title: Text(ui)),
      body: StreamBuilder<List<FlatpakPackage>>(
        stream: repo.fetchByCategory(api),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.brand));
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final apps = snap.data ?? [];
          if (apps.isEmpty) {
            return snap.connectionState == ConnectionState.done
                ? Center(child: Text('No apps in this category',
                    style: Theme.of(context).textTheme.bodyMedium))
                : const Center(
                    child: CircularProgressIndicator(color: AppColors.brand));
          }
          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.pageH),
            itemCount: apps.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) {
              final app = apps[i];
              final grad = AppColors.gradientFor(app.id);
              return RepaintBoundary(
                key: ValueKey(app.id),
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AppDetailPage(package: app))),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(AppSpacing.rLg),
                      border: Border.all(color: context.colors.border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppSpacing.rSm),
                          gradient: LinearGradient(colors: grad),
                        ),
                        child: Center(
                          child: app.icon != null
                              ? CachedNetworkImage(
                                  imageUrl: app.icon!, width: 28, height: 28,
                                  memCacheWidth: 56, fit: BoxFit.contain,
                                  placeholder: (_, __) => const Icon(
                                      Icons.apps_rounded, color: Colors.white),
                                  errorWidget: (_, __, ___) => const Icon(
                                      Icons.apps_rounded, color: Colors.white))
                              : const Icon(Icons.apps_rounded, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(app.name, maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(app.summary ?? '', maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
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
