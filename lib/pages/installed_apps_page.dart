import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/flatpak_bloc.dart';
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
    final repo = context.read<FlatpakRepository>();
    final apps = await repo.getInstalledAppsRobust();

    if (!mounted) return;

    setState(() {
      _installedApps = apps;
      _isLoading = false;
    });

    // Background metadata enrichment (safe, async)
    repo.enrichMissingDetails(apps);
  }

  /// 🔥 Remove app locally as soon as uninstall finishes
  void _removeLocally(String appId) {
    setState(() {
      _installedApps.removeWhere((a) => a.id == appId || a.flatpakId == appId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<FlatpakBloc, FlatpakState>(
      listener: (context, state) {
        if (state is FlatpakLoaded) {
          // Sync local list with bloc-installed set
          _installedApps.removeWhere(
            (app) => !state.installed.contains(app.id),
          );
        }
      },
      child: BlocBuilder<FlatpakBloc, FlatpakState>(
        builder: (context, state) {
          final uninstallingIds = state is FlatpakLoaded
              ? state.uninstallingIds
              : const <String>{};

          return Scaffold(
            backgroundColor: Colors.white,
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    slivers: [
                      // ============================
                      // HEADER
                      // ============================
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(20, 60, 20, 30),
                          child: Text(
                            "Installed Apps",
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      // ============================
                      // EMPTY STATE
                      // ============================
                      if (_installedApps.isEmpty)
                        const SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: Text("No apps installed"),
                            ),
                          ),
                        ),

                      // ============================
                      // APP LIST
                      // ============================
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final app = _installedApps[index];
                          final isUninstalling = uninstallingIds.contains(
                            app.id,
                          );

                          return _InstalledAppCard(
                            app: app,
                            isUninstalling: isUninstalling,
                            onLaunch: () async {
                              try {
                                await FlatpakPlatform.launch(app.id);
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Launch failed: $e")),
                                );
                              }
                            },
                            onUninstall: () {
                              context.read<FlatpakBloc>().add(
                                UninstallApp(app.id),
                              );
                            },
                          );
                        }, childCount: _installedApps.length),
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// =======================================================
/// CARD
/// =======================================================
class _InstalledAppCard extends StatelessWidget {
  final FlatpakPackage app;
  final bool isUninstalling;
  final VoidCallback onLaunch;
  final VoidCallback onUninstall;

  const _InstalledAppCard({
    required this.app,
    required this.isUninstalling,
    required this.onLaunch,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ============================
          // LEFT: INFO + LAUNCH
          // ============================
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  app.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "v${app.version ?? 'Latest'}",
                  style: TextStyle(fontSize: 14, color: Colors.blueGrey[400]),
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
                    ),
                    child: const Text("Launch"),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // ============================
          // RIGHT: CARD + UNINSTALL
          // ============================
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4DB6AC),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: app.icon != null
                          ? Image.network(app.icon!, width: 40, height: 40)
                          : const Icon(
                              Icons.apps,
                              size: 40,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ============================
                // UNINSTALL BUTTON (BLOCKED)
                // ============================
                SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: isUninstalling ? null : onUninstall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: isUninstalling
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text("Uninstalling..."),
                            ],
                          )
                        : const Text("Uninstall"),
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
