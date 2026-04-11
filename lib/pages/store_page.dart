import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  List<AppItem> _apps = [];
  bool _loading = false;
  String? _error;
  int _offset = 0;
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool refresh = true}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (refresh) _offset = 0;
    });

    final api = context.read<ApiService>();
    final items = await api.fetchApps(limit: _pageSize, offset: refresh ? 0 : _offset);

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (refresh) {
        _apps = items;
      } else {
        _apps.addAll(items);
      }
      _offset += items.length;
      if (items.isEmpty && !refresh) {
        _error = 'No more apps';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.store_rounded, color: Color(0xFF00D4FF), size: 20),
            SizedBox(width: 8),
            Text('AGL App Store'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00D4FF)),
            onPressed: () => _load(refresh: true),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _apps.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
      );
    }

    if (_apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Color(0xFF445566), size: 64),
            const SizedBox(height: 16),
            Text(
              _error ?? 'No apps found',
              style: const TextStyle(color: Color(0xFF667788)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _load(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00D4FF),
                side: const BorderSide(color: Color(0xFF00D4FF)),
              ),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notif) {
        if (notif is ScrollEndNotification &&
            notif.metrics.pixels >= notif.metrics.maxScrollExtent - 100 &&
            !_loading) {
          _load(refresh: false);
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        color: const Color(0xFF00D4FF),
        backgroundColor: const Color(0xFF12121A),
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280,
            childAspectRatio: 1.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _apps.length + (_loading ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == _apps.length) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
              );
            }
            return _AppCard(app: _apps[i]);
          },
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  final AppItem app;

  const _AppCard({required this.app});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2A3A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: app.iconUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              app.iconUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.apps_rounded, color: Color(0xFF00D4FF), size: 22),
                            ),
                          )
                        : const Icon(Icons.apps_rounded, color: Color(0xFF00D4FF), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFDDDDEE),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'v${app.version}',
                          style: const TextStyle(
                            color: Color(0xFF556677),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  app.description.isNotEmpty ? app.description : 'No description',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF888899),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              if (app.category != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2A3A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF224455)),
                  ),
                  child: Text(
                    app.category!,
                    style: const TextStyle(
                      color: Color(0xFF00D4FF),
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12121A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF222233)),
        ),
        title: Text(
          app.name,
          style: const TextStyle(color: Color(0xFF00D4FF), fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Version', app.version),
            if (app.category != null) _row('Category', app.category!),
            if (app.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Description:', style: TextStyle(color: Color(0xFF556677), fontSize: 12)),
              const SizedBox(height: 4),
              Text(app.description, style: const TextStyle(color: Color(0xFFAAAAAB), fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF00D4FF))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D4FF)),
            child: const Text('Install', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: Color(0xFF556677), fontSize: 12)),
          Text(value, style: const TextStyle(color: Color(0xFFCCCCDD), fontSize: 12)),
        ],
      ),
    );
  }
}
