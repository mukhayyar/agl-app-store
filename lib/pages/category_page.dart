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

  static const _categories = <_CategoryDef>[
    _CategoryDef(
      uiName: 'Navigation',
      apiCategory: 'Science',
      icon: Icons.map_outlined,
      gradient: [Color(0xFF22C55E), Color(0xFF14B8A6)],
    ),
    _CategoryDef(
      uiName: 'Music',
      apiCategory: 'AudioVideo',
      icon: Icons.headphones_rounded,
      gradient: [Color(0xFFEC4899), Color(0xFFF97316)],
    ),
    _CategoryDef(
      uiName: 'Tools',
      apiCategory: 'Development',
      icon: Icons.build_rounded,
      gradient: [Color(0xFFF59E0B), Color(0xFFEF4444)],
    ),
    _CategoryDef(
      uiName: 'Games',
      apiCategory: 'Game',
      icon: Icons.sports_esports_rounded,
      gradient: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    ),
    _CategoryDef(
      uiName: 'Productivity',
      apiCategory: 'Office',
      icon: Icons.calendar_today_rounded,
      gradient: [Color(0xFF0EA5E9), Color(0xFF14B8A6)],
    ),
    _CategoryDef(
      uiName: 'Utilities',
      apiCategory: 'Utility',
      icon: Icons.layers_rounded,
      gradient: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    ),
    _CategoryDef(
      uiName: 'Entertainment',
      apiCategory: 'AudioVideo',
      icon: Icons.movie_creation_rounded,
      gradient: [Color(0xFF1F2937), Color(0xFF374151)],
    ),
    _CategoryDef(
      uiName: 'Communication',
      apiCategory: 'Network',
      icon: Icons.chat_bubble_rounded,
      gradient: [Color(0xFFF97316), Color(0xFFEC4899)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageGutter,
            AppSpacing.lg,
            AppSpacing.pageGutter,
            0,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Browse',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Find apps by category',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ),
                  ),
                  SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: AppSpacing.lg,
                      mainAxisSpacing: AppSpacing.lg,
                      childAspectRatio: 0.95,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _CategoryCard(def: _categories[i]),
                      childCount: _categories.length,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.huge),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CategoryDef {
  final String uiName;
  final String apiCategory;
  final IconData icon;
  final List<Color> gradient;

  const _CategoryDef({
    required this.uiName,
    required this.apiCategory,
    required this.icon,
    required this.gradient,
  });
}

class _CategoryCard extends StatelessWidget {
  final _CategoryDef def;
  const _CategoryCard({required this.def});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategoryResultsPage(
                uiName: def.uiName,
                apiCategory: def.apiCategory,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            gradient: LinearGradient(
              colors: def.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: def.gradient.last.withValues(alpha: 0.30),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -25,
                top: -25,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
              ),
              Positioned(
                left: -10,
                bottom: -20,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
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
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: Icon(def.icon, color: Colors.white, size: 28),
                    ),
                    Text(
                      def.uiName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- RESULTS PAGE ---
class CategoryResultsPage extends StatelessWidget {
  final String uiName;
  final String apiCategory;

  const CategoryResultsPage({
    super.key,
    required this.uiName,
    required this.apiCategory,
  });

  @override
  Widget build(BuildContext context) {
    final repo = context.read<FlatpakRepository>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(uiName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<FlatpakPackage>>(
        stream: repo.fetchByCategory(apiCategory),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final apps = snapshot.data ?? [];
          if (apps.isEmpty) {
            if (snapshot.connectionState == ConnectionState.done) {
              return Center(
                child: Text(
                  'No apps found in this category',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.pageGutter),
            itemCount: apps.length,
            separatorBuilder: (c, i) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final app = apps[index];
              return RepaintBoundary(
                key: ValueKey(app.id),
                child: _CategoryAppCard(app: app),
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryAppCard extends StatelessWidget {
  final FlatpakPackage app;
  const _CategoryAppCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final gradient = AppColors.gradientFor(app.id);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AppDetailPage(package: app)),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: app.icon != null
                      ? CachedNetworkImage(
                          imageUrl: app.icon!,
                          width: 32,
                          height: 32,
                          memCacheWidth: 64,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Icon(
                            Icons.apps_rounded,
                            color: Colors.white,
                          ),
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.apps_rounded,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.apps_rounded, color: Colors.white),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
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
                      app.summary ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
