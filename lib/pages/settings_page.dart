import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // State dummy untuk simulasi toggle switch
  bool _isDarkMode = false;
  bool _autoUpdate = false;
  bool _locationAccess = false;
  bool _contactsAccess = false;
  bool _cameraAccess = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Title
              const Text(
                "Settings",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 32),

              // --- App Storage Location ---
              _buildSectionHeader("App storage location"),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFF0F4F8,
                  ), // Warna abu-abu muda sesuai gambar
                  borderRadius: BorderRadius.circular(12),
                ),
                // Kosong seperti di desain, atau bisa diisi Text path
              ),
              const SizedBox(height: 32),

              // --- App Appearance ---
              _buildSectionHeader("App appearance"),
              _buildSwitchTile(
                title: "Switch display",
                subtitle: "Change into light or dark mode",
                value: _isDarkMode,
                onChanged: (val) => setState(() => _isDarkMode = val),
              ),
              const SizedBox(height: 24),

              // --- App Updates ---
              _buildSectionHeader("App updates"),
              _buildSwitchTile(
                title: "Auto-update apps",
                subtitle: "Automatically update apps when connected to Wi-Fi",
                value: _autoUpdate,
                onChanged: (val) => setState(() => _autoUpdate = val),
              ),
              const SizedBox(height: 24),

              // --- Permissions ---
              _buildSectionHeader("Permissions"),
              _buildSwitchTile(
                title: "Location access",
                subtitle: "Allow apps to access your location",
                value: _locationAccess,
                onChanged: (val) => setState(() => _locationAccess = val),
              ),
              _buildSwitchTile(
                title: "Contacts access",
                subtitle: "Allow apps to access your contacts",
                value: _contactsAccess,
                onChanged: (val) => setState(() => _contactsAccess = val),
              ),
              _buildSwitchTile(
                title: "Camera access",
                subtitle: "Allow apps to access your camera",
                value: _cameraAccess,
                onChanged: (val) => setState(() => _cameraAccess = val),
              ),
              const SizedBox(height: 24),

              // --- About ---
              _buildSectionHeader("About"),
              const SizedBox(height: 12),
              _buildInfoRow(
                title: "Car ID",
                value: "3849f1c6-f27f-4652-94ea-f86919b44420",
              ),
              const SizedBox(height: 16),
              _buildInfoRow(title: "App Store Version", value: "Version 1.2.3"),

              const SizedBox(
                height: 100,
              ), // Padding bawah agar tidak tertutup navbar
            ],
          ),
        ),
      ),
    );
  }

  // Widget Helper untuk Judul Section (misal: "App appearance")
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }

  // Widget Helper untuk Baris dengan Switch
  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color:
                        Colors.blueGrey[300], // Warna teks deskripsi agak pudar
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor:
                  Colors.black, // Hitam saat aktif (sesuai tema minimalis)
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFE0E0E0), // Abu-abu saat mati
            ),
          ),
        ],
      ),
    );
  }

  // Widget Helper untuk Info Text (Car ID, Version)
  Widget _buildInfoRow({required String title, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, color: Colors.black87),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF638CA5), // Warna biru keabu-abuan sesuai gambar
          ),
        ),
      ],
    );
  }
}
