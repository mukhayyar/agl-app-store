# PENS AGL App Store (Flutter Linux Desktop)

Aplikasi **PENS AGL App Store** berbasis Flutter yang berjalan di **Linux desktop**.  
Menyediakan antarmuka sederhana untuk mencari, menginstal, memperbarui, dan menghapus aplikasi Flatpak dari [Flathub](https://flathub.org).

---

## ✨ Fitur

- 🔍 Cari aplikasi berdasarkan **nama** atau **App ID**
- 📦 Lihat daftar aplikasi dengan ikon, ringkasan, versi, ukuran, dan developer
- ⬇️ Instal aplikasi dari Flathub
- 🔄 Update aplikasi terpasang
- ❌ Uninstall aplikasi
- 📋 Copy App ID ke clipboard
- 📜 Deskripsi aplikasi via API Flathub
- ⚡ **Non-blocking install**: proses instalasi berjalan di thread terpisah agar UI tidak freeze
- 📂 Cache aplikasi lokal menggunakan **sembast database**

---

## 🛠️ Teknologi

- [Flutter](https://flutter.dev/) — UI framework
- [flutter_bloc](https://pub.dev/packages/flutter_bloc) — state management
- [http](https://pub.dev/packages/http) — API client
- [sembast](https://pub.dev/packages/sembast) — local cache database
- [MethodChannel](https://docs.flutter.dev/platform-integration/platform-channels) + **C++ plugin** untuk integrasi `flatpak` CLI

---

## 📦 Instalasi

### Prasyarat
- Linux (Ubuntu / Fedora / distro lain dengan Flatpak support)
- [Flatpak](https://flatpak.org/setup/) sudah terpasang
- [Flutter SDK](https://docs.flutter.dev/get-started/install/linux)

### Clone repository
```bash
git clone https://github.com/username/flathub_store.git
cd flathub_store
