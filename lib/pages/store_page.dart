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
    final expiryInfo = getExpiryInfo(app.expiresAt);

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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                app.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFDDDDEE),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (app.isVerified) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF003A3A),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF00D4FF), width: 0.5),
                                ),
                                child: const Text(
                                  '\u2713 Verified',
                                  style: TextStyle(
                                    color: Color(0xFF00D4FF),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
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
              const SizedBox(height: 6),
              Row(
                children: [
                  if (app.category != null) ...[
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
                    const SizedBox(width: 6),
                  ],
                  if (expiryInfo != null)
                    _ExpiryChip(info: expiryInfo),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final expiryInfo = getExpiryInfo(app.expiresAt);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12121A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF222233)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                app.name,
                style: const TextStyle(color: Color(0xFF00D4FF), fontWeight: FontWeight.bold),
              ),
            ),
            if (app.isVerified) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF003A3A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF00D4FF), width: 0.5),
                ),
                child: const Text(
                  '\u2713 Verified by AGL Store',
                  style: TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Version', app.version),
              if (app.developer != null) _row('Developer', app.developer!),
              if (app.license != null) _row('License', app.license!),
              if (app.category != null) _row('Category', app.category!),
              if (app.expiresAt != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Certificate expires: ',
                          style: TextStyle(color: Color(0xFF556677), fontSize: 12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDate(app.expiresAt!),
                              style: TextStyle(
                                color: expiryInfo != null
                                    ? _expiryTextColor(expiryInfo.level)
                                    : const Color(0xFFCCCCDD),
                                fontSize: 12,
                              ),
                            ),
                            if (expiryInfo != null) ...[
                              const SizedBox(height: 2),
                              _ExpiryChip(info: expiryInfo),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (app.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Description:', style: TextStyle(color: Color(0xFF556677), fontSize: 12)),
                const SizedBox(height: 4),
                Text(app.description, style: const TextStyle(color: Color(0xFFAAAAAB), fontSize: 13)),
              ],
              const SizedBox(height: 12),
              const Text('Install command:', style: TextStyle(color: Color(0xFF556677), fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0F),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF222233)),
                ),
                child: SelectableText(
                  'flatpak install repo.agl-store.cyou ${app.id}',
                  style: const TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
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

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '\${months[dt.month - 1]} \${dt.day}, \${dt.year}';
  }

    Color _expiryTextColor(ExpiryLevel level) {
    switch (level) {
      case ExpiryLevel.critical:
        return const Color(0xFFFF4444);
      case ExpiryLevel.warning:
        return const Color(0xFFFF8800);
      case ExpiryLevel.notice:
        return const Color(0xFFCCCC00);
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: Color(0xFF556677), fontSize: 12)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFFCCCCDD), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _ExpiryChip extends StatelessWidget {
  final ExpiryInfo info;
  const _ExpiryChip({required this.info});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (info.level) {
      case ExpiryLevel.critical:
        bg = const Color(0xFF3A0000);
        fg = const Color(0xFFFF4444);
        break;
      case ExpiryLevel.warning:
        bg = const Color(0xFF3A1A00);
        fg = const Color(0xFFFF8800);
        break;
      case ExpiryLevel.notice:
        bg = const Color(0xFF2A2A00);
        fg = const Color(0xFFCCCC00);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        info.label,
        style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w600),
      ),
    );
  }
}
