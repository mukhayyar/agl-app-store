import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/flatpak_bloc.dart';
import '../models/flatpak_package.dart';
import '../platform/flatpak_platform.dart';

class AppDetailPage extends StatelessWidget {
  final FlatpakPackage package;

  const AppDetailPage({super.key, required this.package});

  static bool _looksLikeFlatpakId(String id) {
    if (!id.contains('.')) return false;
    final parts = id.split('.');
    for (int i = 0; i < parts.length; i++) {
      final isLast = i == parts.length - 1;
      final re = RegExp(isLast ? r'^[A-Za-z0-9_-]+$' : r'^[A-Za-z0-9_]+$');
      if (!re.hasMatch(parts[i])) return false;
    }
    return true;
  }

  static String normalizeFlatpakId(String raw) {
    if (raw.isEmpty) return raw;

    // If it already looks valid, return as-is
    if (_looksLikeFlatpakId(raw)) return raw;

    // 🔥 HACK: convert underscores to dots
    final normalized = raw.replaceAll('_', '.');

    // If the normalized version is valid, use it
    if (_looksLikeFlatpakId(normalized)) {
      debugPrint('Flatpak ID normalized: "$raw" → "$normalized"');
      return normalized;
    }

    // Last resort: return original (will be rejected later)
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FlatpakBloc, FlatpakState>(
      builder: (context, state) {
        bool isInstalled = false;
        bool isInstalling = false;
        int? progress;

        if (state is FlatpakLoaded) {
          final id = normalizeFlatpakId(package.flatpakId);
          isInstalled = state.installed.contains(id);
          isInstalling = state.installingIds.contains(id);
          progress = state.installProgress[id];
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
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _hero(),
                _header(),
                _meta(),
                _description(),
                if (package.screenshots.isNotEmpty) _screenshots(),
                const SizedBox(height: 30),
                _actionButton(
                  context,
                  isInstalled: isInstalled,
                  isInstalling: isInstalling,
                  progress: progress,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================
  // HERO
  // =========================
  Widget _hero() {
    return Container(
      height: 200,
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade900, Colors.blueGrey.shade700],
        ),
      ),
      child: Center(
        child: package.icon != null
            ? Image.network(package.icon!, height: 90)
            : const Icon(Icons.apps, size: 90, color: Colors.white24),
      ),
    );
  }

  // =========================
  // HEADER
  // =========================
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        package.name,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
    );
  }

  // =========================
  // META (developer, version, license)
  // =========================
  Widget _meta() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          if (package.developerName != null)
            _chip(Icons.business, package.developerName!),
          if (package.version != null) _chip(Icons.tag, package.version!),
          if (package.license != null) _chip(Icons.gavel, package.license!),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Chip(avatar: Icon(icon, size: 16), label: Text(text));
  }

  // =========================
  // DESCRIPTION
  // =========================
  Widget _description() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        package.description ?? package.summary ?? 'No description available.',
        style: TextStyle(
          color: Colors.blueGrey[700],
          height: 1.6,
          fontSize: 15,
        ),
      ),
    );
  }

  // =========================
  // SCREENSHOTS
  // =========================
  Widget _screenshots() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text(
            'Screenshots',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 240,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: package.screenshots.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  package.screenshots[i],
                  width: 320,
                  fit: BoxFit.cover,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================
  // ACTION BUTTON
  // =========================
  Widget _actionButton(
    BuildContext context, {
    required bool isInstalled,
    required bool isInstalling,
    required int? progress,
  }) {
    final id = normalizeFlatpakId(package.flatpakId);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: isInstalling
              ? null
              : isInstalled
              ? () => FlatpakPlatform.launch(id)
              : () => context.read<FlatpakBloc>().add(InstallApp(id)),
          style: ElevatedButton.styleFrom(
            backgroundColor: isInstalled
                ? Colors.grey.shade300
                : const Color(0xFF1976D2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: isInstalling
              ? Text(
                  progress != null ? 'Installing $progress%' : 'Installing…',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Text(
                  isInstalled ? 'Launch' : 'Install',
                  style: TextStyle(
                    color: isInstalled ? Colors.black : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
