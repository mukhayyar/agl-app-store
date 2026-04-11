import 'package:flutter/material.dart';

import '../models/flatpak_package.dart';
import '../pages/app_detail_page.dart';

class _CategoryAppCard extends StatelessWidget {
  final FlatpakPackage app;
  const _CategoryAppCard({required this.app});

  @override
  Widget build(BuildContext context) {
    // We import AppDetailPage to allow navigation (optional)
    // import '../pages/app_detail_page.dart';

    return GestureDetector(
      onTap: () {
        // Optional: Add navigation to detail page if you have imported it
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AppDetailPage(package: app)),
        );
      },
      child: Card(
        elevation: 0,
        color: Colors.grey[50],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: ListTile(
          leading: app.icon != null
              ? Image.network(
                  app.icon!,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.apps),
                )
              : const Icon(Icons.apps),
          title: Text(
            app.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            app.summary ?? "",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
