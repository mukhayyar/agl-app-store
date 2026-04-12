import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../services/api_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _urlController;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsModel>();
    _urlController = TextEditingController(text: settings.apiBaseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final settings = context.read<SettingsModel>();
    final api = context.read<ApiService>();

    await settings.setApiBaseUrl(url);
    api.updateBaseUrl(url);

    setState(() => _saved = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _saved = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.settings_rounded, color: Color(0xFF00D4FF), size: 20),
            SizedBox(width: 8),
            Text('Settings'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'API Configuration'),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AGL Backend URL',
                      style: TextStyle(
                        color: Color(0xFF888899),
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlController,
                      style: const TextStyle(color: Color(0xFFCCCCDD), fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'http://localhost:8002',
                        hintStyle: const TextStyle(color: Color(0xFF445566)),
                        prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF556677)),
                        filled: true,
                        fillColor: const Color(0xFF0D0D18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF222233)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF222233)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF00D4FF)),
                        ),
                      ),
                      onSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _save,
                        icon: Icon(
                          _saved ? Icons.check_rounded : Icons.save_rounded,
                          size: 18,
                        ),
                        label: Text(_saved ? 'Saved!' : 'Save & Apply'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _saved ? const Color(0xFF00AA55) : const Color(0xFF00D4FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            _SectionHeader(title: 'Connection Status'),
            const SizedBox(height: 16),
            const _PingStatusCard(),
            const SizedBox(height: 32),
            _SectionHeader(title: 'About'),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _AboutRow(icon: Icons.info_outline_rounded, label: 'App', value: 'AGL IVI Monitor'),
                    _AboutRow(icon: Icons.tag_rounded, label: 'Version', value: '1.0.0'),
                    _AboutRow(icon: Icons.computer_rounded, label: 'Platform', value: 'Linux (AGL)'),
                    _AboutRow(
                      icon: Icons.code_rounded,
                      label: 'Package',
                      value: 'com.agl.ivi_monitor',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF00D4FF),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }
}

class _PingStatusCard extends StatelessWidget {
  const _PingStatusCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<ApiService>(
      builder: (context, api, _) {
        final isOnline = api.pingLatencyMs >= 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? const Color(0xFF00FF88) : const Color(0xFFFF4444),
                    boxShadow: [
                      BoxShadow(
                        color: (isOnline ? const Color(0xFF00FF88) : const Color(0xFFFF4444))
                            .withOpacity(0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOnline ? 'Connected' : 'Unreachable',
                        style: TextStyle(
                          color: isOnline ? const Color(0xFF00FF88) : const Color(0xFFFF4444),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        api.baseUrl,
                        style: const TextStyle(color: Color(0xFF556677), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (isOnline)
                  Text(
                    '${api.pingLatencyMs.toStringAsFixed(0)} ms',
                    style: const TextStyle(
                      color: Color(0xFF00D4FF),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AboutRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AboutRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF445566), size: 18),
          const SizedBox(width: 12),
          Text('$label:', style: const TextStyle(color: Color(0xFF667788), fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFFCCCCDD), fontSize: 13),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
