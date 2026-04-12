import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

enum _Repo { pensHub, flathub }

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
  _Repo _repo = _Repo.pensHub;

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
    final List<AppItem> items;
    if (_repo == _Repo.flathub) {
      items = await api.fetchFlathubApps(limit: _pageSize, offset: refresh ? 0 : _offset);
    } else {
      items = await api.fetchApps(limit: _pageSize, offset: refresh ? 0 : _offset);
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (refresh) {
        _apps = items;
      } else {
        _apps.addAll(items);
      }
      _offset += items.length;
      if (items.isEmpty && !refresh) _error = 'No more apps';
    });
  }

  void _switchRepo(_Repo repo) {
    if (_repo == repo) return;
    setState(() {
      _repo = repo;
      _apps = [];
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isPens = _repo == _Repo.pensHub;
    final accentColor = isPens ? const Color(0xFF00D4FF) : const Color(0xFFFF6B35);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.store_rounded, color: accentColor, size: 20),
            const SizedBox(width: 8),
            Text(isPens ? 'AGL App Store' : 'Flathub',
                style: TextStyle(color: accentColor)),
          ],
        ),
        actions: [
          // Source toggle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF222233)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RepoTab(
                  label: 'PensHub',
                  icon: Icons.storefront_rounded,
                  selected: _repo == _Repo.pensHub,
                  activeColor: const Color(0xFF00D4FF),
                  onTap: () => _switchRepo(_Repo.pensHub),
                ),
                _RepoTab(
                  label: 'Flathub',
                  icon: Icons.public_rounded,
                  selected: _repo == _Repo.flathub,
                  activeColor: const Color(0xFFFF6B35),
                  onTap: () => _switchRepo(_Repo.flathub),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: accentColor),
            onPressed: () => _load(refresh: true),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(accentColor),
    );
  }

  Widget _buildBody(Color accentColor) {
    if (_loading && _apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: accentColor),
            const SizedBox(height: 16),
            Text(
              _repo == _Repo.flathub ? 'Loading from Flathub...' : 'Loading from PensHub...',
              style: const TextStyle(color: Color(0xFF667788)),
            ),
          ],
        ),
      );
    }

    if (_apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Color(0xFF445566), size: 64),
            const SizedBox(height: 16),
            Text(_error ?? 'No apps found',
                style: const TextStyle(color: Color(0xFF667788))),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _load(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                side: BorderSide(color: accentColor),
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
        color: accentColor,
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
              return Center(child: CircularProgressIndicator(color: accentColor));
            }
            return _AppCard(app: _apps[i], repo: _repo);
          },
        ),
      ),
    );
  }
}

// ── Repo Tab Button ──────────────────────────────────────────────────────────

class _RepoTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  const _RepoTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? activeColor : const Color(0xFF556677)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? activeColor : const Color(0xFF556677),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── App Card ─────────────────────────────────────────────────────────────────

class _AppCard extends StatelessWidget {
  final AppItem app;
  final _Repo repo;

  const _AppCard({required this.app, required this.repo});

  Color get _accentColor =>
      repo == _Repo.pensHub ? const Color(0xFF00D4FF) : const Color(0xFFFF6B35);

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
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.apps_rounded,
                                color: _accentColor,
                                size: 22,
                              ),
                            ),
                          )
                        : Icon(Icons.apps_rounded, color: _accentColor, size: 22),
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
                          app.version.isNotEmpty ? 'v${app.version}' : app.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF556677), fontSize: 11),
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
                        style: TextStyle(
                          color: _accentColor,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (expiryInfo != null) _ExpiryChip(info: expiryInfo),
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
    final isPens = repo == _Repo.pensHub;
    final accentColor = isPens ? const Color(0xFF00D4FF) : const Color(0xFFFF6B35);
    final installCmd = isPens
        ? 'flatpak install penshub ${app.id}'
        : 'flatpak install flathub ${app.id}';

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
              child: Text(app.name,
                  style: TextStyle(
                      color: accentColor, fontWeight: FontWeight.bold)),
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
                      fontWeight: FontWeight.w600),
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
              if (app.version.isNotEmpty) _row('Version', app.version),
              if (app.developer != null) _row('Developer', app.developer!),
              if (app.license != null) _row('License', app.license!),
              if (app.category != null) _row('Category', app.category!),
              _row('Source', isPens ? 'PensHub (AGL Store)' : 'Flathub'),
              if (app.expiresAt != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cert expires: ',
                          style: TextStyle(color: Color(0xFF556677), fontSize: 12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDate(app.expiresAt!),
                              style: TextStyle(
                                color: expiryInfo != null
                                    ? _expiryColor(expiryInfo.level)
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
                const Text('Description:',
                    style: TextStyle(color: Color(0xFF556677), fontSize: 12)),
                const SizedBox(height: 4),
                Text(app.description,
                    style: const TextStyle(color: Color(0xFFAAAAAB), fontSize: 13)),
              ],
              const SizedBox(height: 12),
              const Text('Install:',
                  style: TextStyle(color: Color(0xFF556677), fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0F),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF222233)),
                ),
                child: SelectableText(
                  installCmd,
                  style: TextStyle(
                    color: accentColor,
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
            child: Text('Close', style: TextStyle(color: accentColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            child: const Text('Install', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(color: Color(0xFF556677), fontSize: 12)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(color: Color(0xFFCCCCDD), fontSize: 12)),
            ),
          ],
        ),
      );

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Color _expiryColor(ExpiryLevel level) {
    switch (level) {
      case ExpiryLevel.critical: return const Color(0xFFFF4444);
      case ExpiryLevel.warning:  return const Color(0xFFFF8800);
      case ExpiryLevel.notice:   return const Color(0xFFCCCC00);
    }
  }
}

// ── Expiry Chip ──────────────────────────────────────────────────────────────

class _ExpiryChip extends StatelessWidget {
  final ExpiryInfo info;
  const _ExpiryChip({required this.info});

  @override
  Widget build(BuildContext context) {
    Color bg; Color fg;
    switch (info.level) {
      case ExpiryLevel.critical:
        bg = const Color(0xFF3A0000); fg = const Color(0xFFFF4444); break;
      case ExpiryLevel.warning:
        bg = const Color(0xFF3A1A00); fg = const Color(0xFFFF8800); break;
      case ExpiryLevel.notice:
        bg = const Color(0xFF2A2A00); fg = const Color(0xFFCCCC00); break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withOpacity(0.5), width: 0.5),
      ),
      child: Text(info.label,
          style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}
