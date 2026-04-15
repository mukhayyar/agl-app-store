import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/pressable.dart';
import 'about_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoUpdate = false;
  bool _locationAccess = false;
  bool _contactsAccess = false;
  bool _cameraAccess = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeSvc = context.watch<ThemeService>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageH, AppSpacing.lg, AppSpacing.pageH, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: theme.textTheme.displaySmall),
                const SizedBox(height: AppSpacing.xxxl),

                // --- App Storage Location ---
                _SectionHeader('App storage location'),
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(AppSpacing.rMd),
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text('/var/lib/flatpak',
                      style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: AppSpacing.xxxl),

                // --- App Appearance ---
                _SectionHeader('App appearance'),
                _SwitchTile(
                  title: 'Dark mode',
                  subtitle: 'Switch between light and dark theme',
                  value: themeSvc.isDark,
                  onChanged: (val) => themeSvc.setDark(val),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // --- App Updates ---
                _SectionHeader('App updates'),
                _SwitchTile(
                  title: 'Auto-update apps',
                  subtitle: 'Automatically update apps when connected to Wi-Fi',
                  value: _autoUpdate,
                  onChanged: (val) => setState(() => _autoUpdate = val),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // --- Permissions ---
                _SectionHeader('Permissions'),
                _SwitchTile(
                  title: 'Location access',
                  subtitle: 'Allow apps to access your location',
                  value: _locationAccess,
                  onChanged: (val) => setState(() => _locationAccess = val),
                ),
                _SwitchTile(
                  title: 'Contacts access',
                  subtitle: 'Allow apps to access your contacts',
                  value: _contactsAccess,
                  onChanged: (val) => setState(() => _contactsAccess = val),
                ),
                _SwitchTile(
                  title: 'Camera access',
                  subtitle: 'Allow apps to access your camera',
                  value: _cameraAccess,
                  onChanged: (val) => setState(() => _cameraAccess = val),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // --- About ---
                _SectionHeader('About'),
                const SizedBox(height: AppSpacing.md),
                _InfoRow(
                  title: 'Car ID',
                  value: '3849f1c6-f27f-4652-94ea-f86919b44420',
                ),
                const SizedBox(height: AppSpacing.lg),
                _AboutLink(),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.brand,
            activeTrackColor: AppColors.brandSoft,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String value;
  const _InfoRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Link row navigating to the full About page (system info, versions).
class _AboutLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AboutPage()),
      ),
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(AppSpacing.rMd),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: context.colors.cardEl,
                borderRadius: BorderRadius.circular(AppSpacing.rSm),
              ),
              child: Icon(Icons.info_outline_rounded,
                  size: 18, color: context.colors.textS),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ABOUT',
                    style: TextStyle(
                      color: context.colors.textT,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Versions, system info',
                    style: TextStyle(
                      color: context.colors.textP,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: context.colors.textT, size: 20),
          ],
        ),
      ),
    );
  }
}
