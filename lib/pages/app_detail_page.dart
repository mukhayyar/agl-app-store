import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/flatpak_bloc.dart'; // Adjust path as needed
import '../models/flatpak_package.dart'; // Adjust path as needed
import '../platform/flatpak_platform.dart'; // Adjust path as needed

class AppDetailPage extends StatefulWidget {
  final FlatpakPackage package;

  const AppDetailPage({super.key, required this.package});

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  // Logic to show install progress (Reused from Home Page)
  void _showInstallProgress(BuildContext context) {
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

            if (m['appId'] != widget.package.id) return;

            switch (m['type']) {
              case 'stdout':
                final ln = (m['line'] ?? '').toString();
                if (ln.trim().isNotEmpty) lines.value = [...lines.value, ln];
                break;
              case 'stderr':
                final ln = (m['line'] ?? '').toString();
                if (ln.trim().isNotEmpty)
                  lines.value = [...lines.value, 'ERR: $ln'];
                break;
              case 'done':
                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                break;
            }
          } catch (_) {}
        });

        return WillPopScope(
          onWillPop: () async => false,
          child: Container(
            height: 400,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(width: 12),
                    Text(
                      'Processing...',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
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
                          reverse: true,
                          child: Text(
                            v.join(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
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
      // Refresh the Bloc so the button state updates to "Installed"
      context.read<FlatpakBloc>().add(
        LoadFirstPage(query: widget.package.name),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Process Complete')));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen to Bloc to update button state (Install vs Uninstall)
    return BlocBuilder<FlatpakBloc, FlatpakState>(
      builder: (context, state) {
        bool isInstalled = false;
        if (state is FlatpakLoaded) {
          isInstalled = state.installed.contains(widget.package.id);
        }

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: CircleAvatar(
                  backgroundImage: NetworkImage(
                    'https://i.pravatar.cc/150?img=5',
                  ),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. HERO IMAGE (Placeholder as per design)
                Container(
                  height: 180,
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        Colors.blueGrey.shade900,
                        Colors.blueGrey.shade700,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Using the App Icon if available, else text
                            widget.package.icon != null
                                ? Image.network(
                                    widget.package.icon!,
                                    height: 80,
                                  )
                                : const Icon(
                                    Icons.apps,
                                    size: 80,
                                    color: Colors.white24,
                                  ),
                            const SizedBox(height: 10),
                            const Text(
                              "AGL SafeWork",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 18,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 2. HEADER INFO
                      Text(
                        widget.package.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Developed by ${widget.package.developerName ?? 'Unknown'} | Version: ${widget.package.version ?? 'Latest'}",
                        style: TextStyle(
                          color: Colors.blueGrey[400],
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 3. RATING SECTION (Static UI to match design)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "4.5",
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: List.generate(
                                  5,
                                  (index) => Icon(
                                    index < 4 ? Icons.star : Icons.star_half,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "1,234 reviews",
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 30),
                          // Progress Bars
                          Expanded(
                            child: Column(
                              children: [
                                _buildRatingRow(5, 0.6),
                                _buildRatingRow(4, 0.3),
                                _buildRatingRow(3, 0.1),
                                _buildRatingRow(2, 0.05),
                                _buildRatingRow(1, 0.02),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // 4. DESCRIPTION
                      Text(
                        widget.package.description ??
                            widget.package.summary ??
                            "No description available.",
                        style: TextStyle(
                          color: Colors.blueGrey[700],
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 5. SCREENSHOTS (Title)
                      const Text(
                        "Screenshots",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // 6. SCREENSHOTS LIST (Horizontal)
                SizedBox(
                  height: 250,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: 3,
                    separatorBuilder: (_, __) => const SizedBox(width: 15),
                    itemBuilder: (context, index) {
                      return Container(
                        width: 140,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        // Placeholder images because API doesn't provide screenshots in current model
                        child: Center(
                          child: Icon(
                            Icons.image,
                            size: 50,
                            color: Colors.grey[300],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 30),

                // 7. ACTION BUTTONS (The Logic)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  child: Column(
                    children: [
                      if (!isInstalled)
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () {
                              _showInstallProgress(context);
                              context.read<FlatpakBloc>().add(
                                InstallApp(widget.package.id),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1976D2), // Blue
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "Install",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () async {
                              // 1. Show feedback immediately
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Launching app..."),
                                  duration: Duration(
                                    seconds: 1,
                                  ), // Short duration
                                ),
                              );

                              // 2. Call the platform method
                              try {
                                await FlatpakPlatform.launch(widget.package.id);
                              } catch (e) {
                                // 3. Handle errors (like if flatpak run fails)
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "Failed to launch: ${e.toString()}",
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE0E0E0), // Grey
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "Launch",
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () {
                              // Confirmation Dialog
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text("Uninstall?"),
                                  content: Text(
                                    "Remove ${widget.package.name}?",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text("Cancel"),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _showInstallProgress(
                                          context,
                                        ); // Reuse progress UI for uninstall logs
                                        context.read<FlatpakBloc>().add(
                                          UninstallApp(widget.package.id),
                                        );
                                      },
                                      child: const Text(
                                        "Uninstall",
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC62828), // Red
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "Uninstall",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper for the Rating bars
  Widget _buildRatingRow(int star, double pct) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Text(
            "$star",
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "${(pct * 100).toInt()}%",
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
