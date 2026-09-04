import 'package:flutter/material.dart';

import '../services/fabularium_session_service.dart';
import '../services/supabase_service.dart';
import 'fabularium_login_page.dart';
import 'fabularium_shell_page.dart';
import 'telegram_connection_page.dart';

class FabulariumEntryGate
    extends StatelessWidget {
  final String fabulariumPath;

  const FabulariumEntryGate({
    super.key,
    required this.fabulariumPath,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final session =
        FabulariumSessionService.instance;

    return AnimatedBuilder(
      animation:
          session,
      builder:
          (
        context,
        _,
      ) {
        switch (session.stage) {
          case FabulariumSessionStage.initializing:
            return const _BootstrapPage();

          case FabulariumSessionStage
                .fabulariumAuthentication:
            return const FabulariumLoginPage();

          case FabulariumSessionStage
                .telegramAuthentication:
            return const TelegramConnectionPage();

          case FabulariumSessionStage.ready:
            return FabulariumShellPage(
              fabulariumPath:
                  fabulariumPath,
            );

          case FabulariumSessionStage
                .configurationError:
            return _ConfigurationErrorPage(
              error:
                  SupabaseService
                          .instance
                          .initializationError ??
                      session.error,
            );
        }
      },
    );
  }
}

class _BootstrapPage
    extends StatelessWidget {
  const _BootstrapPage();

  @override
  Widget build(
    BuildContext context,
  ) {
    return const Scaffold(
      body:
          Center(
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children:
              <Widget>[
            Icon(
              Icons.auto_awesome,
              size:
                  58,
            ),
            SizedBox(
              height:
                  18,
            ),
            CircularProgressIndicator(),
            SizedBox(
              height:
                  14,
            ),
            Text(
              'Restoring Fabularium session...',
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigurationErrorPage
    extends StatelessWidget {
  final Object? error;

  const _ConfigurationErrorPage({
    required this.error,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      body:
          Center(
        child:
            Padding(
          padding:
              const EdgeInsets.all(
            32,
          ),
          child:
              ConstrainedBox(
            constraints:
                const BoxConstraints(
              maxWidth:
                  620,
            ),
            child:
                Column(
              mainAxisSize:
                  MainAxisSize.min,
              children:
                  <Widget>[
                Icon(
                  Icons.settings_outlined,
                  size:
                      64,
                  color:
                      Theme.of(
                    context,
                  )
                          .colorScheme
                          .error,
                ),
                const SizedBox(
                  height:
                      16,
                ),
                Text(
                  'Fabularium configuration error',
                  style:
                      Theme.of(
                    context,
                  )
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight:
                                FontWeight.bold,
                          ),
                ),
                const SizedBox(
                  height:
                      10,
                ),
                const Text(
                  'Supabase must be configured before the application can start.',
                  textAlign:
                      TextAlign.center,
                ),
                if (error !=
                    null) ...<Widget>[
                  const SizedBox(
                    height:
                        12,
                  ),
                  SelectableText(
                    error.toString(),
                    textAlign:
                        TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
