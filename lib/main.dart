import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/flatpak_bloc.dart';
import 'data/flatpak_repository.dart';
import 'models/flatpak_package.dart';
import 'platform/flatpak_platform.dart';
import 'pages/category_page.dart';
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
    return RepositoryProvider(
      create: (context) => FlatpakRepository(),
      child: BlocProvider(
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
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
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
            Text('AGL App Store'),
          ],
        ),
        actions: [
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
                            final installed = state.installed.contains(
                              pkg.flatpakId,
                            );
                            // Check if this specific app is installing
                            final isInstalling = state.installingIds.contains(
                              pkg.id,
                            );

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
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
                                  isInstalling: isInstalling, // Pass state
                                  cardColor: _getColorFromId(pkg.id),
                                  onInstall: () {
                                    if (!installed && !isInstalling) {
                                      // No blocking modal. Just dispatch event.
                                      bloc.add(InstallApp(pkg.flatpakId));
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "Downloading ${pkg.name}...",
                                          ),
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

  Color _getColorFromId(String id) {
    final int hash = id.codeUnits.fold(0, (prev, element) => prev + element);
    final Random rng = Random(hash);
    return Color.fromARGB(
      255,
      50 + rng.nextInt(100),
      50 + rng.nextInt(100),
      50 + rng.nextInt(100),
    );
  }
}

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

class AppListItem extends StatelessWidget {
  final FlatpakPackage package;
  final bool isInstalled;
  final bool isInstalling; // NEW: Receive installing state
  final Color cardColor;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  const AppListItem({
    super.key,
    required this.package,
    required this.isInstalled,
    required this.isInstalling,
    required this.cardColor,
    required this.onInstall,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
              if (isInstalling)
                // SHOW SPINNER
                ElevatedButton.icon(
                  onPressed: null,
                  icon: const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  label: const Text('Installing...'),
                )
              else if (isInstalled)
                Row(
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
              else
                ElevatedButton(
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
