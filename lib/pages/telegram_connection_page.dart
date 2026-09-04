import 'package:flutter/material.dart';

import '../services/fabularium_session_service.dart';
import '../services/telegram_service.dart';

class TelegramConnectionPage
    extends StatefulWidget {
  const TelegramConnectionPage({
    super.key,
  });

  @override
  State<TelegramConnectionPage>
      createState() =>
          _TelegramConnectionPageState();
}

class _TelegramConnectionPageState
    extends State<TelegramConnectionPage> {
  final FabulariumSessionService _session =
      FabulariumSessionService.instance;

  final TelegramService _telegram =
      TelegramService.instance;

  final TextEditingController _phone =
      TextEditingController(
    text:
        '+55',
  );

  final TextEditingController _code =
      TextEditingController();

  final TextEditingController _password =
      TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();

    super.dispose();
  }

  Future<void> _useAnotherAccount() async {
    try {
      await _session.signOutAll();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content:
              Text(
            error.toString(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      body:
          Center(
        child:
            SingleChildScrollView(
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
              children:
                  <Widget>[
                const Icon(
                  Icons.auto_awesome,
                  size:
                      64,
                ),
                const SizedBox(
                  height:
                      14,
                ),
                Text(
                  'FABULARIUM',
                  style:
                      Theme.of(
                    context,
                  )
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                            fontWeight:
                                FontWeight.bold,
                            letterSpacing:
                                2,
                          ),
                ),
                const SizedBox(
                  height:
                      18,
                ),
                const _ConnectionFlow(),
                const SizedBox(
                  height:
                      24,
                ),
                Card(
                  child:
                      Padding(
                    padding:
                        const EdgeInsets.all(
                      28,
                    ),
                    child:
                        Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children:
                          <Widget>[
                        const Icon(
                          Icons.cloud_download_outlined,
                          size:
                              52,
                        ),
                        const SizedBox(
                          height:
                              14,
                        ),
                        Text(
                          'Connect Telegram',
                          textAlign:
                              TextAlign.center,
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
                              8,
                        ),
                        const Text(
                          'Fabularium uses Telegram as the transfer network for large files. '
                          'This connection is part of your Fabularium session and must be completed before entering the app.',
                          textAlign:
                              TextAlign.center,
                        ),
                        const SizedBox(
                          height:
                              8,
                        ),
                        const Text(
                          'You will not need to browse channels or use Telegram separately.',
                          textAlign:
                              TextAlign.center,
                        ),
                        const SizedBox(
                          height:
                              26,
                        ),
                        _buildState(),
                        const SizedBox(
                          height:
                              14,
                        ),
                        TextButton.icon(
                          onPressed:
                              _session.isSigningOut
                                  ? null
                                  : _useAnotherAccount,
                          icon:
                              const Icon(
                            Icons.switch_account_outlined,
                          ),
                          label:
                              const Text(
                            'Use another Fabularium account',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildState() {
    if (_session.isCheckingTelegram ||
        _telegram.state ==
            TelegramAuthState.connecting) {
      return const Center(
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children:
              <Widget>[
            CircularProgressIndicator(),
            SizedBox(
              height:
                  12,
            ),
            Text(
              'Checking saved Telegram session...',
            ),
          ],
        ),
      );
    }

    switch (_telegram.state) {
      case TelegramAuthState.disconnected:
      case TelegramAuthState.phoneRequired:
        return _form(
          title:
              'Phone number',
          controller:
              _phone,
          button:
              'Send Verification Code',
          icon:
              Icons.phone_outlined,
          onSubmit:
              () =>
                  _telegram.sendCode(
            _phone.text,
          ),
        );

      case TelegramAuthState.codeRequired:
        return _form(
          title:
              'Verification code',
          controller:
              _code,
          button:
              'Continue',
          icon:
              Icons.password_outlined,
          onSubmit:
              () =>
                  _telegram.signIn(
            _code.text,
          ),
        );

      case TelegramAuthState.passwordRequired:
        return _form(
          title:
              'Two-step verification password',
          controller:
              _password,
          button:
              'Continue',
          icon:
              Icons.lock_outline,
          obscure:
              true,
          onSubmit:
              () =>
                  _telegram.checkPassword(
            _password.text,
          ),
        );

      case TelegramAuthState.error:
        return Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children:
              <Widget>[
            Text(
              _telegram.errorMessage ??
                  'Telegram connection error.',
              textAlign:
                  TextAlign.center,
              style:
                  TextStyle(
                color:
                    Theme.of(
                  context,
                )
                        .colorScheme
                        .error,
              ),
            ),
            const SizedBox(
              height:
                  16,
            ),
            FilledButton.tonalIcon(
              onPressed:
                  _session.ensureTelegramSession,
              icon:
                  const Icon(
                Icons.refresh,
              ),
              label:
                  const Text(
                'Try Again',
              ),
            ),
          ],
        );

      case TelegramAuthState.authenticated:
        return const Center(
          child:
              Column(
            mainAxisSize:
                MainAxisSize.min,
            children:
                <Widget>[
              Icon(
                Icons.check_circle_outline,
                size:
                    48,
              ),
              SizedBox(
                height:
                    10,
              ),
              Text(
                'Telegram connected. Opening Fabularium...',
              ),
            ],
          ),
        );

      case TelegramAuthState.connecting:
        return const SizedBox.shrink();
    }
  }

  Widget _form({
    required String title,
    required TextEditingController controller,
    required String button,
    required IconData icon,
    required Future<void> Function() onSubmit,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children:
          <Widget>[
        TextField(
          controller:
              controller,
          obscureText:
              obscure,
          onSubmitted:
              (_) =>
                  onSubmit(),
          decoration:
              InputDecoration(
            labelText:
                title,
            prefixIcon:
                Icon(
              icon,
            ),
            border:
                const OutlineInputBorder(),
          ),
        ),
        const SizedBox(
          height:
              16,
        ),
        FilledButton(
          onPressed:
              onSubmit,
          child:
              Text(
            button,
          ),
        ),
      ],
    );
  }
}

class _ConnectionFlow
    extends StatelessWidget {
  const _ConnectionFlow();

  @override
  Widget build(
    BuildContext context,
  ) {
    final primary =
        Theme.of(
      context,
    )
            .colorScheme
            .primary;

    return Row(
      mainAxisAlignment:
          MainAxisAlignment.center,
      children:
          <Widget>[
        CircleAvatar(
          radius:
              15,
          backgroundColor:
              primary,
          foregroundColor:
              Theme.of(
            context,
          )
                  .colorScheme
                  .onPrimary,
          child:
              const Icon(
            Icons.check,
            size:
                16,
          ),
        ),
        const SizedBox(
          width:
              7,
        ),
        Text(
          'Fabularium',
          style:
              TextStyle(
            color:
                primary,
          ),
        ),
        Container(
          margin:
              const EdgeInsets.symmetric(
            horizontal:
                12,
          ),
          width:
              60,
          height:
              1,
          color:
              Theme.of(
            context,
          )
                  .dividerColor,
        ),
        CircleAvatar(
          radius:
              15,
          backgroundColor:
              primary,
          foregroundColor:
              Theme.of(
            context,
          )
                  .colorScheme
                  .onPrimary,
          child:
              const Text(
            '2',
          ),
        ),
        const SizedBox(
          width:
              7,
        ),
        Text(
          'Telegram',
          style:
              TextStyle(
            color:
                primary,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
