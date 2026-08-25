import 'package:flutter/material.dart';

import 'pages/catalog_page.dart';
import 'pages/download_queue_page.dart';
import 'services/performance_monitor.dart';
import 'services/telegram_performance_coordinator.dart';
import 'widgets/download_queue_overlay.dart';

final GlobalKey<NavigatorState>
    rootNavigatorKey =
    GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding
      .ensureInitialized();

  PerformanceMonitor.instance
      .start();

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
    final performance =
        TelegramPerformanceCoordinator.instance;

    return MaterialApp(
      navigatorKey:
          rootNavigatorKey,
      navigatorObservers: [
        performance,
      ],
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
        return Listener(
          behavior:
              HitTestBehavior.translucent,
          onPointerDown:
              (_) {
            performance
                .noteInteraction();
          },
          onPointerMove:
              (_) {
            performance
                .noteInteraction();
          },
          onPointerSignal:
              (_) {
            performance
                .noteInteraction();
          },
          child:
              Stack(
            children: [
              if (child !=
                  null)
                child,
              DownloadQueueOverlay(
                onOpen:
                    _openDownloads,
              ),
            ],
          ),
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

    if (navigator ==
        null) {
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
