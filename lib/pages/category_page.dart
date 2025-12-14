import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/flatpak_repository.dart';
import '../models/flatpak_package.dart';
// You might need to import your AppListItem component if you want to reuse it for the results page
// import 'home_page.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Categories',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              backgroundColor: Colors.grey[200],
              child: const Icon(Icons.settings_outlined, color: Colors.black),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=5'),
            ),
          ),
        ],
      ),
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

class CategoryResultsPage extends StatefulWidget {
  final String uiName;
  final String apiCategory;

  const CategoryResultsPage({
    super.key,
    required this.uiName,
    required this.apiCategory,
  });

  @override
  State<CategoryResultsPage> createState() => _CategoryResultsPageState();
}

class _CategoryResultsPageState extends State<CategoryResultsPage> {
  List<FlatpakPackage> _apps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Access your repo (assuming you are using Provider/GetIt/Bloc to retrieve it)
    // For this snippet I'm creating a new instance, but you should use context.read<FlatpakRepository>() if available
    final repo = FlatpakRepository();
    final apps = await repo.fetchByCategory(widget.apiCategory);

    if (mounted) {
      setState(() {
        _apps = apps;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.uiName),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _apps.isEmpty
          ? const Center(child: Text("No apps found in this category"))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _apps.length,
              separatorBuilder: (c, i) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final app = _apps[index];
                return Card(
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
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.apps),
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
                );
              },
            ),
    );
  }
}
