import 'package:flutter/material.dart';

import 'config/fabularium_config.dart';
import 'features/community/application/community_auth_service.dart';
import 'pages/download_queue_page.dart';
import 'pages/fabularium_shell_page.dart';
import 'services/performance_monitor.dart';
import 'services/supabase_service.dart';
import 'services/telegram_performance_coordinator.dart';
import 'widgets/download_queue_overlay.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseService.instance.initialize();
  await CommunityAuthService.instance.initialize();

  PerformanceMonitor.instance.start();

  runApp(const FabulariumApp());
}

class FabulariumApp extends StatelessWidget {
  const FabulariumApp({super.key});

  @override
  Widget build(BuildContext context) {
    final performance = TelegramPerformanceCoordinator.instance;

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [performance],
      title: 'Fabularium',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
      ),
      builder: (context, child) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => performance.noteInteraction(),
          onPointerMove: (_) => performance.noteInteraction(),
          onPointerSignal: (_) => performance.noteInteraction(),
          child: Stack(
            children: [
              ?child,
              DownloadQueueOverlay(onOpen: _openDownloads),
            ],
          ),
        );
      },
      home: const FabulariumShellPage(
        fabulariumPath: FabulariumConfig.rootPath,
      ),
    );
  }

  void _openDownloads() {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      MaterialPageRoute(
        builder: (_) => const DownloadQueuePage(),
      ),
    );
  }
}
