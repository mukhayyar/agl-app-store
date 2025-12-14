import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/flatpak_repository.dart';
import '../models/flatpak_package.dart';
import '../platform/flatpak_platform.dart';

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
    // 1. Get list of ID strings from the Platform Channel
    final installedIds = await FlatpakPlatform.listInstalled();

    // 2. Fetch details (Name, Icon, Version) for each ID using the Repo
    //    (Assuming you have access to the repository via context or direct instance)
    final repo = context.read<FlatpakRepository>();

    final List<FlatpakPackage> loadedApps = [];

    for (final appId in installedIds) {
      // Try to find in cache first, or fetch fresh
      // You might need to add a 'fetchDetails' or 'getCached' method to your repo
      // For now, we assume fetchDetails works.
      var pkg = await repo.fetchDetails(appId);

      // Fallback if API fails: create a basic package with just the ID
      pkg ??= FlatpakPackage(
        id: appId,
        name: appId, // Use ID as name if detail fetch fails
        summary: "Installed Application",
      );

      loadedApps.add(pkg);
    }

    if (mounted) {
      setState(() {
        _installedApps = loadedApps;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Title Header
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 60, 20, 30),
                    child: Text(
                      "Installed Apps",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),

                // Empty State
                if (_installedApps.isEmpty)
                  const SliverToBoxAdapter(
                    child: Center(child: Text("No apps installed")),
                  ),

                // App List
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final app = _installedApps[index];
                    return _InstalledAppCard(
                      app: app,
                      onUninstall: () async {
                        await FlatpakPlatform.uninstall(app.id);
                        _loadInstalledApps(); // Refresh list after uninstall
                      },
                      onLaunch: () async {
                        // Make sure you added the 'launch' method to FlatpakPlatform!
                        // If not, see the note below.
                        try {
                          await FlatpakPlatform.launch(app.id);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Could not launch: $e")),
                          );
                        }
                      },
                    );
                  }, childCount: _installedApps.length),
                ),

                // Bottom padding
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
    );
  }
}

class _InstalledAppCard extends StatelessWidget {
  final FlatpakPackage app;
  final VoidCallback onUninstall;
  final VoidCallback onLaunch;

  const _InstalledAppCard({
    required this.app,
    required this.onUninstall,
    required this.onLaunch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT SIDE: Info & Launch Button
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20), // Visual alignment
                Text(
                  app.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "v${app.version ?? '1.0.0'}",
                  style: TextStyle(fontSize: 14, color: Colors.blue[300]),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: onLaunch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: const Text("Launch"),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // RIGHT SIDE: Card & Uninstall Button
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // The Teal Card
                Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4DB6AC), // Teal color from image
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Decorative Icon Background
                      Positioned(
                        right: -10,
                        bottom: -10,
                        child: Icon(
                          Icons.apps,
                          size: 100,
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      // Main Icon
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.4),
                              width: 2,
                            ),
                          ),
                          child: app.icon != null
                              ? Image.network(app.icon!, width: 40, height: 40)
                              : const Icon(
                                  Icons.touch_app,
                                  color: Colors.white,
                                  size: 40,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Uninstall Button (Right Aligned)
                SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: onUninstall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: const Text("Uninstall"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
