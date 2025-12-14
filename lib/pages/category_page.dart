import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/flatpak_repository.dart';
import '../models/flatpak_package.dart';
import 'app_detail_page.dart';
// import '../widget/category_app_card.dart';
// You might need to import your AppListItem component if you want to reuse it for the results page
// import 'home_page.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive grid: 2 columns on phone, 4 on tablet/desktop
            final int crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

            return GridView.count(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.0, // Square cards
              children: [
                _buildCatCard(
                  context,
                  "Navigation",
                  "Science",
                  Icons.map_outlined,
                  const Color(0xFFC8E6C9),
                ), // Mapping Navigation -> Science (Maps often here)
                _buildCatCard(
                  context,
                  "Music",
                  "AudioVideo",
                  Icons.headphones_outlined,
                  const Color(0xFFFFCCBC),
                ),
                _buildCatCard(
                  context,
                  "Tools",
                  "Development",
                  Icons.build_circle_outlined,
                  const Color(0xFFFFE0B2),
                ),
                _buildCatCard(
                  context,
                  "Games",
                  "Game",
                  Icons.sports_esports,
                  const Color(0xFFB2DFDB),
                ),
                _buildCatCard(
                  context,
                  "Productivity",
                  "Office",
                  Icons.calendar_today_outlined,
                  const Color(0xFFFFF9C4),
                ),
                _buildCatCard(
                  context,
                  "Utilities",
                  "Utility",
                  Icons.layers_outlined,
                  const Color(0xFFCFD8DC),
                ),
                _buildCatCard(
                  context,
                  "Entertainment",
                  "AudioVideo",
                  Icons.movie_creation_outlined,
                  const Color(0xFF263238),
                  iconColor: Colors.white,
                  textColor: Colors.white,
                ), // Using Dark BG like image
                _buildCatCard(
                  context,
                  "Communication",
                  "Network",
                  Icons.chat_bubble_outline,
                  const Color(0xFFFFCCBC),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCatCard(
    BuildContext context,
    String uiName,
    String apiCategory,
    IconData icon,
    Color bgColor, {
    Color iconColor = Colors.black54,
    Color textColor = Colors.black,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CategoryResultsPage(uiName: uiName, apiCategory: apiCategory),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  // Decorative circle opacity for style matching
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      icon,
                      size: 64,
                      color: iconColor.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            uiName,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 16,
              color: textColor == Colors.white ? Colors.black : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

// --- RESULTS PAGE (Shows apps when a category is clicked) ---
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
    // 1. Get the global repository instance (Fixes "new instance" issue)
    final repo = context.read<FlatpakRepository>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(uiName),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      // 2. Use StreamBuilder instead of Future/await
      body: StreamBuilder<List<FlatpakPackage>>(
        stream: repo.fetchByCategory(apiCategory),
        builder: (context, snapshot) {
          // State A: Loading (Initial wait)
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // State B: Error
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          // State C: Empty Data
          final apps = snapshot.data ?? [];
          if (apps.isEmpty) {
            // If connection is done and still empty, show "No apps"
            if (snapshot.connectionState == ConnectionState.done) {
              return const Center(
                child: Text("No apps found in this category"),
              );
            }
            // If still waiting for network but cache was empty, keep spinning
            return const Center(child: CircularProgressIndicator());
          }

          // State D: Show List (Cached or Fresh)
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: apps.length,
            separatorBuilder: (c, i) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final app = apps[index];
              return _CategoryAppCard(app: app);
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
    return GestureDetector(
      // --- UPDATE THIS SECTION ---
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AppDetailPage(package: app)),
        );
      },
      // ---------------------------
      child: Card(
        elevation: 0,
        color: Colors.grey[50],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: ListTile(
          leading: app.icon != null
              ? Image.network(
                  app.icon!,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.apps),
                )
              : const Icon(Icons.apps),
          title: Text(
            app.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            app.summary ?? "",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
