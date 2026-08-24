import 'package:flutter/material.dart';

import 'pages/catalog_page.dart';
import 'pages/download_queue_page.dart';
import 'widgets/download_queue_overlay.dart';

final GlobalKey<NavigatorState>
    rootNavigatorKey =
    GlobalKey<NavigatorState>();

void main() {
  runApp(
    const FabulariumApp(),
  );
}

class FabulariumApp
    extends StatelessWidget {
  const FabulariumApp({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      navigatorKey:
          rootNavigatorKey,
      title:
          'Fabularium',
      debugShowCheckedModeBanner:
          false,
      theme:
          ThemeData(
        useMaterial3:
            true,
        colorSchemeSeed:
            Colors.deepPurple,
      ),
      builder:
          (
        context,
        child,
      ) {
        return Stack(
          children: [
            if (child != null)
              child,

            DownloadQueueOverlay(
              onOpen:
                  _openDownloads,
            ),
          ],
        );
      },
      home:
          const CatalogPage(
        fabulariumPath:
            r'D:\Fabularium',
      ),
    );
  }

  void _openDownloads() {
    final navigator =
        rootNavigatorKey
            .currentState;

    if (navigator == null) {
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder:
            (_) =>
                const DownloadQueuePage(),
      ),
    );
  }
}