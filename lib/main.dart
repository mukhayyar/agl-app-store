import 'dart:async';
import 'dart:convert';
import 'dart:math'; // Used for generating random UI colors based on ID

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/flatpak_bloc.dart';
import 'data/flatpak_repository.dart';
import 'models/flatpak_package.dart';
import 'platform/flatpak_platform.dart';
import 'pages/category_page.dart'; // Make sure this file exists
import 'pages/app_detail_page.dart';
import 'pages/installed_apps_page.dart';
import 'pages/settings_page.dart';

void main() {
  runApp(const FlatpakApp());
}

class FlatpakApp extends StatelessWidget {
  const FlatpakApp({super.key});

  @override
  Widget build(BuildContext context) {
    // KITA HAPUS inisialisasi manual di sini
    // final repo = FlatpakRepository(); <-- Hapus baris ini

    // GUNAKAN RepositoryProvider
    return RepositoryProvider(
      create: (context) => FlatpakRepository(),
      child: BlocProvider(
        // Sekarang Bloc mengambil repo dari context yang sudah disediakan di atasnya
        create: (context) =>
            FlatpakBloc(repo: context.read<FlatpakRepository>())
              ..add(const RefreshAll()),
        child: MaterialApp(
          title: 'AGL App Store',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.white,
            primaryColor: Colors.black,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.black),
              titleTextStyle: TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            fontFamily: 'sans-serif',
          ),
          home: const FlatpakHomePage(),
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
  int _selectedIndex = 0; // For the bottom nav bar visual

  @override
  void initState() {
    super.initState();
    // Pagination Logic integrated into the new ScrollController
    _scrollCtl.addListener(() {
      if (!mounted) return;
      final bloc = context.read<FlatpakBloc>();
      if (_scrollCtl.position.pixels >=
          _scrollCtl.position.maxScrollExtent - 400) {
        bloc.add(const LoadNextPage());
      }
    });
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  // --- Your Existing Logic Preserved Below ---
  void _showInstallProgress(String appId) {
    final stream = FlatpakPlatform.installEvents();
    late final StreamSubscription sub;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (ctx) {
        final lines = ValueNotifier<List<String>>(<String>[]);
        sub = stream.listen((event) {
          try {
            final Map<String, dynamic> m = event is String
                ? jsonDecode(event)
                : (event as Map).cast<String, dynamic>();
            if (m['appId'] != appId) return;

            switch (m['type']) {
              case 'stdout':
                final ln = (m['line'] ?? '').toString();
                if (ln.trim().isNotEmpty) lines.value = [...lines.value, ln];
                break;
              case 'stderr':
                final ln = (m['line'] ?? '').toString();
                if (ln.trim().isNotEmpty) {
                  lines.value = [...lines.value, 'ERR: $ln'];
                }
                break;
              case 'done':
                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                break;
            }
          } catch (_) {}
        });

        return WillPopScope(
          onWillPop: () async => false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(width: 12),
                    Text(
                      'Installing application...',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ValueListenableBuilder<List<String>>(
                        valueListenable: lines,
                        builder: (_, v, __) => SingleChildScrollView(
                          child: Text(
                            v.join(),
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      sub.cancel();
      final bloc = context.read<FlatpakBloc>();
      final s = bloc.state;
      if (s is FlatpakLoaded) {
        bloc.add(LoadFirstPage(query: s.query));
      } else {
        bloc.add(const LoadFirstPage());
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Installation Complete')));
    });
  }

  // --- UI Construction ---

  @override
  @override
  Widget build(BuildContext context) {
    final bloc = context.read<FlatpakBloc>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.apps, color: Colors.black),
            SizedBox(width: 10),
            // Change Title dynamically based on tab
            Text('AGL App Store'),
          ],
        ),
        actions: [
          // Only show search bar on Home Tab (Index 0) to keep Categories clean
          if (_selectedIndex == 0)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: const Icon(Icons.search, color: Colors.black54),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Search"),
                      content: TextField(
                        controller: _searchCtl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: "App Name...",
                        ),
                        onSubmitted: (q) {
                          bloc.add(
                            LoadFirstPage(query: q.trim().isEmpty ? null : q),
                          );
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  );
                },
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

      // --- THIS IS THE KEY CHANGE ---
      // If selectedIndex is 1, show CategoriesPage.
      // Otherwise, show the existing BlocConsumer (Home Feed).
      body: _selectedIndex == 1
          ? const CategoriesPage()
          : _selectedIndex == 2
          ? const InstalledAppsPage()
          : _selectedIndex == 3
          ? const SettingsPage()
          : BlocConsumer<FlatpakBloc, FlatpakState>(
              listener: (context, state) {
                if (state is FlatpakError) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(state.message)));
                }
              },
              builder: (context, state) {
                if (state is FlatpakLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is FlatpakError) {
                  return Center(
                    child: TextButton(
                      onPressed: () => bloc.add(const RefreshAll()),
                      child: const Text("Error. Tap to Retry"),
                    ),
                  );
                }

                if (state is FlatpakLoaded) {
                  final items = state.items;
                  if (items.isEmpty) {
                    return const Center(child: Text("No apps found"));
                  }

                  final featuredItems = items.take(3).toList();
                  final listItems = items.skip(3).toList();

                  return CustomScrollView(
                    controller: _scrollCtl,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: featuredItems.map((pkg) {
                                    // --- CHANGE 1: WRAP FEATURED CARD ---
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AppDetailPage(package: pkg),
                                          ),
                                        );
                                      },
                                      child: FeaturedCard(
                                        package: pkg,
                                        color: _getColorFromId(pkg.id),
                                      ),
                                    );
                                    // ------------------------------------
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 30),
                              const Text(
                                "All Apps",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= listItems.length) {
                              return state.hasMore
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : const SizedBox(height: 50);
                            }
                            final pkg = listItems[index];
                            final installed = state.installed.contains(pkg.id);

                            // --- CHANGE 2: WRAP APP LIST ITEM ---
                            return GestureDetector(
                              behavior: HitTestBehavior
                                  .opaque, // Ensures clicks work on empty space
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AppDetailPage(package: pkg),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: AppListItem(
                                  package: pkg,
                                  isInstalled: installed,
                                  cardColor: _getColorFromId(pkg.id),
                                  onInstall: () {
                                    if (!installed) {
                                      _showInstallProgress(pkg.id);
                                      bloc.add(InstallApp(pkg.id));
                                    }
                                  },
                                  onUninstall: () =>
                                      bloc.add(UninstallApp(pkg.id)),
                                ),
                              ),
                            );
                            // ------------------------------------
                          },
                          childCount:
                              listItems.length + (state.hasMore ? 1 : 0),
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          // Only refresh if tapping the Home tab while already on Home
          if (index == 0 && _selectedIndex == 0) {
            bloc.add(const RefreshAll());
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        backgroundColor: Colors.white,
        elevation: 10,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: "Categories"),
          BottomNavigationBarItem(
            icon: Icon(Icons.branding_watermark),
            label: "Installed",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: "Settings",
          ),
        ],
      ),
    );
  }

  // Helper to generate a consistent pastel color from a string ID
  Color _getColorFromId(String id) {
    final int hash = id.codeUnits.fold(0, (prev, element) => prev + element);
    final Random rng = Random(hash);
    // Darker pastel shades suitable for white text/icons
    return Color.fromARGB(
      255,
      50 + rng.nextInt(100),
      50 + rng.nextInt(100),
      50 + rng.nextInt(100),
    );
  }
}

// ==========================================
// COMPONENT 1: Featured Card
// ==========================================
class FeaturedCard extends StatelessWidget {
  final FlatpakPackage package;
  final Color color;

  const FeaturedCard({super.key, required this.package, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                // Background Pattern (Placeholder)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.2,
                    child: Image.network(
                      "https://images.unsplash.com/photo-1552086971-da0cb107297e?auto=format&fit=crop&q=80&w=300",
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                ),
                // Actual Icon
                Center(child: _AppIcon(url: package.icon, size: 60)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            package.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            package.summary ?? "No description available",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.blueGrey[400], fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// COMPONENT 2: List Item
// ==========================================
class AppListItem extends StatelessWidget {
  final FlatpakPackage package;
  final bool isInstalled;
  final Color cardColor;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  const AppListItem({
    super.key,
    required this.package,
    required this.isInstalled,
    required this.cardColor,
    required this.onInstall,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left Side: Text Info
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                package.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                package.summary ?? "",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.blueGrey[400], fontSize: 14),
              ),
              const SizedBox(height: 16),
              isInstalled
                  ? Row(
                      children: [
                        const Text(
                          "Installed",
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          onPressed: onUninstall,
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: "Uninstall",
                        ),
                      ],
                    )
                  : ElevatedButton(
                      onPressed: onInstall,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text("Install"),
                    ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        // Right Side: Graphic Card
        Expanded(
          flex: 5,
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _AppIcon(url: package.icon, size: 50),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Helper widget for loading icons safely
class _AppIcon extends StatelessWidget {
  final String? url;
  final double size;

  const _AppIcon({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return Icon(Icons.apps, size: size, color: Colors.white);
    }
    return Image.network(
      url!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.broken_image, size: size, color: Colors.white),
    );
  }
}
