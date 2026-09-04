import 'dart:async';

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

  StreamSubscription<TelegramAuthState>?
      _subscription;

  String? _busyLabel;

  bool get _isBusy =>
      _busyLabel !=
      null;

  @override
  void initState() {
    super.initState();

    _subscription =
        _telegram.stateStream.listen(
      (_) {
        if (mounted) {
          setState(() {});
        }
      },
    );

    unawaited(
      _runAction(
        'Connecting to Telegram...',
        _telegram.connect,
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();

    _phone.dispose();
    _code.dispose();
    _password.dispose();

    super.dispose();
  }

  Future<void> _runAction(
    String label,
    Future<void> Function() action,
  ) async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _busyLabel =
          label;
    });

    try {
      await action();
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
    } finally {
      if (mounted) {
        setState(() {
          _busyLabel =
              null;
        });
      }
    }
  }

  Future<void> _sendCode() {
    return _runAction(
      'Sending verification code...',
      () =>
          _telegram.sendCode(
        _phone.text,
      ),
    );
  }

  Future<void> _signIn() {
    return _runAction(
      'Verifying code...',
      () =>
          _telegram.signIn(
        _code.text,
      ),
    );
  }

  Future<void> _checkPassword() {
    return _runAction(
      'Checking two-step password...',
      () =>
          _telegram.checkPassword(
        _password.text,
      ),
    );
  }

  Future<void> _retryConnection() {
    return _runAction(
      'Reconnecting to Telegram...',
      _telegram.connect,
    );
  }

  Future<void> _useAnotherAccount() {
    return _runAction(
      'Signing out...',
      _session.useAnotherFabulariumAccount,
    );
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
                          'This connection must be ready before entering the app.',
                          textAlign:
                              TextAlign.center,
                        ),
                        const SizedBox(
                          height:
                              8,
                        ),
                        const Text(
                          'You do not need to browse channels or use Telegram separately.',
                          textAlign:
                              TextAlign.center,
                        ),
                        const SizedBox(
                          height:
                              26,
                        ),
                        _buildState(),
                        if (_busyLabel !=
                            null) ...<Widget>[
                          const SizedBox(
                            height:
                                16,
                          ),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children:
                                <Widget>[
                              const SizedBox(
                                width:
                                    18,
                                height:
                                    18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth:
                                      2,
                                ),
                              ),
                              const SizedBox(
                                width:
                                    10,
                              ),
                              Flexible(
                                child:
                                    Text(
                                  _busyLabel!,
                                  textAlign:
                                      TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(
                          height:
                              14,
                        ),
                        TextButton.icon(
                          onPressed:
                              _isBusy ||
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
    switch (_telegram.state) {
      case TelegramAuthState.connecting:
        return const _CenteredProgress(
          label:
              'Connecting to Telegram...',
        );

      case TelegramAuthState.phoneRequired:
      case TelegramAuthState.disconnected:
        return _form(
          title:
              'Phone number',
          controller:
              _phone,
          button:
              _isBusy
                  ? 'Sending...'
                  : 'Send Verification Code',
          icon:
              Icons.phone_outlined,
          onSubmit:
              _sendCode,
        );

      case TelegramAuthState.codeRequired:
        return _form(
          title:
              'Verification code',
          controller:
              _code,
          button:
              _isBusy
                  ? 'Verifying...'
                  : 'Continue',
          icon:
              Icons.password_outlined,
          onSubmit:
              _signIn,
        );

      case TelegramAuthState.passwordRequired:
        return _form(
          title:
              'Two-step verification password',
          controller:
              _password,
          button:
              _isBusy
                  ? 'Checking...'
                  : 'Continue',
          icon:
              Icons.lock_outline,
          obscure:
              true,
          onSubmit:
              _checkPassword,
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

      case TelegramAuthState.error:
        return Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children:
              <Widget>[
            Icon(
              Icons.error_outline,
              size:
                  42,
              color:
                  Theme.of(
                context,
              )
                      .colorScheme
                      .error,
            ),
            const SizedBox(
              height:
                  12,
            ),
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
                  _isBusy
                      ? null
                      : _retryConnection,
              icon:
                  _isBusy
                      ? const SizedBox(
                          width:
                              18,
                          height:
                              18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2,
                          ),
                        )
                      : const Icon(
                          Icons.refresh,
                        ),
              label:
                  Text(
                _isBusy
                    ? 'Reconnecting...'
                    : 'Try Again',
              ),
            ),
          ],
        );
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
          enabled:
              !_isBusy,
          obscureText:
              obscure,
          onSubmitted:
              (_) {
            if (!_isBusy) {
              onSubmit();
            }
          },
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
        FilledButton.icon(
          onPressed:
              _isBusy
                  ? null
                  : onSubmit,
          icon:
              _isBusy
                  ? const SizedBox(
                      width:
                          18,
                      height:
                          18,
                      child:
                          CircularProgressIndicator(
                        strokeWidth:
                            2,
                      ),
                    )
                  : const Icon(
                      Icons.arrow_forward,
                    ),
          label:
              Text(
            button,
          ),
        ),
      ],
    );
  }
}

class _CenteredProgress
    extends StatelessWidget {
  final String label;

  const _CenteredProgress({
    required this.label,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Center(
      child:
          Column(
        mainAxisSize:
            MainAxisSize.min,
        children:
            <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(
            height:
                12,
          ),
          Text(
            label,
          ),
        ],
      ),
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
