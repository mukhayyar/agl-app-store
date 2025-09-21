import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/flatpak_bloc.dart';
import 'data/flatpak_repository.dart';
import 'models/flatpak_package.dart';
import 'platform/flatpak_platform.dart';

void main() {
  runApp(const FlatpakApp());
}

class FlatpakApp extends StatelessWidget {
  const FlatpakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PENS AGL App Store',
      theme: ThemeData.light(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
      ),
      home: BlocProvider(
        create: (_) => FlatpakBloc(repo: FlatpakRepository())..add(const RefreshAll()),
        child: const FlatpakHomePage(),
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
  final _searchCtl = TextEditingController();
  final _scrollCtl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(() {
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

  void _copyAppId(String appId) {
    Clipboard.setData(ClipboardData(text: appId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ID aplikasi $appId disalin')),
    );
  }

  /// Tampilkan progress install dari EventChannel agar UI tidak freeze
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
            // event dari plugin dikirim sebagai JSON string
            final Map<String, dynamic> m = event is String
                ? jsonDecode(event)
                : (event as Map).cast<String, dynamic>();
            if (m['appId'] != appId) return; // abaikan app lain

            switch (m['type']) {
              case 'stdout':
                final ln = (m['line'] ?? '').toString();
                // flathub sering kirim \r; rapikan seperlunya
                if (ln.trim().isNotEmpty) {
                  lines.value = [...lines.value, ln];
                }
                break;
              case 'stderr':
                final ln = (m['line'] ?? '').toString();
                if (ln.trim().isNotEmpty) {
                  lines.value = [...lines.value, 'ERR: $ln'];
                }
                break;
              case 'done':
                // tutup sheet dan refresh list agar badge "Terpasang" muncul
                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                break;
            }
          } catch (_) {
            // ignore malformed event
          }
        });

        return WillPopScope(
          onWillPop: () async => false, // jangan bisa di-back saat memasang
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
                    Text('Menginstal aplikasi…',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {}, // sengaja disable (biar tak bisa ditutup)
                    icon: const Icon(Icons.downloading),
                    label: const Text('Sedang berjalan…'),
                  ),
                )
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      sub.cancel();
      // setelah selesai, muat ulang halaman pertama dengan query yang sama
      final bloc = context.read<FlatpakBloc>();
      final s = bloc.state;
      if (s is FlatpakLoaded) {
        bloc.add(LoadFirstPage(query: s.query));
      } else {
        bloc.add(const LoadFirstPage());
      }
      // snack kecil
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Instalasi selesai')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<FlatpakBloc>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flathub Store'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => bloc.add(const RefreshAll()),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                hintText: 'Cari nama atau App ID…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onSubmitted: (q) =>
                  bloc.add(LoadFirstPage(query: q.trim().isEmpty ? null : q.trim())),
            ),
          ),
        ),
      ),
      body: BlocConsumer<FlatpakBloc, FlatpakState>(
        listener: (context, state) {
          if (state is FlatpakError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          if (state is FlatpakLoading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Memuat aplikasi dari Flathub...'),
                ],
              ),
            );
          }
          if (state is FlatpakLoaded) {
            if (state.items.isEmpty) {
              return const Center(child: Text('Tidak ada aplikasi yang ditemukan'));
            }
            return ListView.builder(
              controller: _scrollCtl,
              itemCount: state.items.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= state.items.length) {
                  // loader baris terakhir saat hasMore
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final pkg = state.items[index];
                final installed = state.installed.contains(pkg.id);
                return _AppCard(
                  package: pkg,
                  installed: installed,
                  onCopy: () => _copyAppId(pkg.id),
                  onInstall: () {
                    // tampilkan progress stream + trigger install
                    _showInstallProgress(pkg.id);
                    bloc.add(InstallApp(pkg.id));
                  },
                  onUpdate: () => bloc.add(UpdateApp(pkg.id)),
                  onUninstall: () => bloc.add(UninstallApp(pkg.id)),
                );
              },
            );
          }
          if (state is FlatpakError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => bloc.add(const RefreshAll()),
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  final FlatpakPackage package;
  final bool installed;
  final VoidCallback onCopy;
  final VoidCallback onInstall;
  final VoidCallback onUpdate;
  final VoidCallback onUninstall;

  const _AppCard({
    required this.package,
    required this.installed,
    required this.onCopy,
    required this.onInstall,
    required this.onUpdate,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: package.icon != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      package.icon!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _iconFallback(),
                    ),
                  )
                : _iconFallback(),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    package.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (installed)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green[600],
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Terpasang',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((package.summary ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      package.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if ((package.description ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      package.description!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                if ((package.developerName ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Oleh: ${package.developerName}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                if ((package.version ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Versi: ${package.version}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                if ((package.downloadSize ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Ukuran: ${package.downloadSize} MB',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Salin ID'),
                    onPressed: onCopy,
                  ),
                ),
                const SizedBox(width: 8),
                if (!installed) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Instal'),
                      onPressed: onInstall,
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.system_update_alt, size: 18),
                      label: const Text('Update'),
                      onPressed: onUpdate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: const Text('Hapus'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onUninstall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconFallback() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.apps_rounded, color: Colors.grey),
      );
}
