import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/pressable.dart';

/// Informational page: app version, catalog endpoints, flatpak version,
/// device/OS details. Intended to be reachable from Settings and to
/// serve as the go-to source of diagnostic info for support.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _appVersion = '1.0.0+1';
  static const _pensHubApi = 'https://api.agl-store.cyou';
  static const _flathubApi = 'https://flathub.org/api/v2';

  String? _flatpakVersion;
  String? _kernelVersion;

  @override
  void initState() {
    super.initState();
    _loadSystemInfo();
  }

  Future<void> _loadSystemInfo() async {
    // flatpak --version
    String? fp;
    try {
      final r = await Process.run('flatpak', ['--version']);
      if (r.exitCode == 0) fp = r.stdout.toString().trim();
    } catch (_) {
      try {
        final r = await Process.run('/usr/bin/flatpak', ['--version']);
        if (r.exitCode == 0) fp = r.stdout.toString().trim();
      } catch (_) {}
    }
    final kernel = Platform.operatingSystemVersion;
    if (mounted) {
      setState(() {
        _flatpakVersion = fp ?? 'unknown';
        _kernelVersion = kernel;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageH, AppSpacing.xxl, AppSpacing.pageH, AppSpacing.huge),
        children: [
          // ── Hero card ──
          Container(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              color: context.colors.card,
              borderRadius: BorderRadius.circular(AppSpacing.rLg),
              border: Border.all(color: context.colors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: context.colors.cardEl,
                    borderRadius: BorderRadius.circular(AppSpacing.rMd),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Icon(Icons.apps_rounded,
                      color: context.colors.textP, size: 28),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AGL App Store',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('Version $_appVersion',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // ── Catalog sources ──
          _sectionHeader(context, 'CATALOG SOURCES'),
          _infoRow(context,
              icon: Icons.storefront_rounded,
              label: 'PensHub',
              value: _pensHubApi),
          _infoRow(context,
              icon: Icons.public_rounded,
              label: 'Flathub',
              value: _flathubApi),

          const SizedBox(height: AppSpacing.xxl),

          // ── System info ──
          _sectionHeader(context, 'SYSTEM'),
          _infoRow(context,
              icon: Icons.inventory_2_rounded,
              label: 'Flatpak',
              value: _flatpakVersion ?? 'Loading…'),
          _infoRow(context,
              icon: Icons.memory_rounded,
              label: 'Platform',
              value: Platform.operatingSystem),
          _infoRow(context,
              icon: Icons.terminal_rounded,
              label: 'Kernel',
              value: _kernelVersion ?? 'Loading…',
              multiline: true),
          _infoRow(context,
              icon: Icons.location_on_rounded,
              label: 'Hostname',
              value: Platform.localHostname),

          const SizedBox(height: AppSpacing.xxl),

          // ── Attribution ──
          Center(
            child: Text(
              'Built for Automotive Grade Linux',
              style: TextStyle(
                color: context.colors.textT,
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text('© 2026 PENS · AGL App Store',
                style: TextStyle(
                    color: context.colors.textT, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                color: context.colors.textP,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
              )),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Container(height: 1, color: context.colors.border)),
        ],
      ),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool multiline = false,
  }) {
    return Pressable(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied $label'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      pressedScale: 0.99,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(AppSpacing.rMd),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: context.colors.cardEl,
                borderRadius: BorderRadius.circular(AppSpacing.rSm),
              ),
              child: Icon(icon, size: 18, color: context.colors.textS),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: context.colors.textT,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: multiline ? 4 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textP,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.copy_rounded,
                size: 14, color: context.colors.textT),
          ],
        ),
      ),
    );
  }
}
