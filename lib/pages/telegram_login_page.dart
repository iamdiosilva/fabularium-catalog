import 'dart:async';

import 'package:flutter/material.dart';

import '../services/telegram_service.dart';
import 'telegram_group_pages.dart';

class TelegramLoginPage extends StatefulWidget {
  const TelegramLoginPage({
    super.key,
  });

  @override
  State<TelegramLoginPage> createState() =>
      _TelegramLoginPageState();
}

class _TelegramLoginPageState
    extends State<TelegramLoginPage> {
  final TelegramService _telegram =
      TelegramService.instance;

  final TextEditingController _controller =
      TextEditingController();

  final FocusNode _focusNode =
      FocusNode();

  StreamSubscription<TelegramAuthState>?
      _subscription;

  late TelegramAuthState _state;

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();

    _state = _telegram.state;

    _subscription =
        _telegram.stateStream.listen(
      _onStateChanged,
    );

    WidgetsBinding.instance
        .addPostFrameCallback(
      (_) {
        _initializeTelegram();
      },
    );
  }

  Future<void> _initializeTelegram() async {
    if (!mounted) {
      return;
    }

    /*
     * Se já está autenticado,
     * não precisamos fazer nada.
     */
    if (_telegram.isAuthenticated) {
      setState(() {
        _state =
            TelegramAuthState.authenticated;
      });

      return;
    }

    /*
     * Se existe uma sessão salva,
     * conecta automaticamente.
     */
    if (_telegram.hasSavedSession) {
      setState(() {
        _isProcessing = true;
      });

      try {
        await _telegram.connect();
      } finally {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();

    _controller.dispose();
    _focusNode.dispose();

    super.dispose();
  }

  void _onStateChanged(
    TelegramAuthState state,
  ) {
    if (!mounted) {
      return;
    }

    final previousState =
        _state;

    setState(() {
      _state = state;
      _isProcessing = false;
    });

    if (state != previousState) {
      if (state ==
              TelegramAuthState
                  .codeRequired ||
          state ==
              TelegramAuthState
                  .passwordRequired) {
        _controller.clear();

        WidgetsBinding.instance
            .addPostFrameCallback(
          (_) {
            if (mounted) {
              _focusNode.requestFocus();
            }
          },
        );
      }
    }

    if (state ==
        TelegramAuthState.authenticated) {
      _controller.clear();
      _focusNode.unfocus();
    }
  }

  String get _title {
    switch (_state) {
      case TelegramAuthState.disconnected:
        return 'Connect Telegram';

      case TelegramAuthState.connecting:
        return 'Connecting to Telegram';

      case TelegramAuthState.phoneRequired:
        return 'Phone Number';

      case TelegramAuthState.codeRequired:
        return 'Telegram Code';

      case TelegramAuthState.passwordRequired:
        return 'Verification Password';

      case TelegramAuthState.authenticated:
        return 'Telegram Connected';

      case TelegramAuthState.error:
        return 'Telegram Error';
    }
  }

  String get _description {
    switch (_state) {
      case TelegramAuthState.disconnected:
        return 'Connect your Telegram account to Fabularium.';

      case TelegramAuthState.connecting:
        return 'Establishing a secure connection with Telegram...';

      case TelegramAuthState.phoneRequired:
        return 'Enter your phone number including country code.';

      case TelegramAuthState.codeRequired:
        return 'Telegram sent you a login code. Enter it below.';

      case TelegramAuthState.passwordRequired:
        return 'Your account uses two-step verification. Enter your password.';

      case TelegramAuthState.authenticated:
        return 'Your Telegram account is connected and ready.';

      case TelegramAuthState.error:
        return _telegram.errorMessage ??
            'An error occurred while connecting to Telegram.';
    }
  }

  bool get _showInput {
    return _state ==
            TelegramAuthState.phoneRequired ||
        _state ==
            TelegramAuthState.codeRequired ||
        _state ==
            TelegramAuthState.passwordRequired;
  }

  String get _fieldLabel {
    switch (_state) {
      case TelegramAuthState.phoneRequired:
        return 'Phone Number';

      case TelegramAuthState.codeRequired:
        return 'Code';

      case TelegramAuthState.passwordRequired:
        return 'Password';

      default:
        return '';
    }
  }

  bool get _obscureText =>
      _state ==
      TelegramAuthState.passwordRequired;

  TextInputType get _keyboardType {
    switch (_state) {
      case TelegramAuthState.phoneRequired:
        return TextInputType.phone;

      case TelegramAuthState.codeRequired:
        return TextInputType.number;

      default:
        return TextInputType.text;
    }
  }

  Future<void> _onPressed() async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      if (_state ==
              TelegramAuthState.disconnected ||
          _state ==
              TelegramAuthState.error) {
        await _telegram.connect();

        return;
      }

      final value =
          _controller.text.trim();

      if (value.isEmpty) {
        _showMessage(
          'Fill in the field.',
        );

        return;
      }

      if (_state ==
          TelegramAuthState.phoneRequired) {
        await _telegram.sendCode(
          value.replaceAll(
            RegExp(r'\s+'),
            '',
          ),
        );

        return;
      }

      if (_state ==
          TelegramAuthState.codeRequired) {
        await _telegram.signIn(
          value,
        );

        return;
      }

      if (_state ==
          TelegramAuthState.passwordRequired) {
        await _telegram.checkPassword(
          value,
        );
      }
    } catch (e) {
      _showMessage(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _openGroups() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const TelegramGroupsPage(),
      ),
    );
  }

  Future<void> _logout() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await _telegram.logout();
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final authenticated =
        _state ==
            TelegramAuthState.authenticated;

    final loading =
        _state ==
                TelegramAuthState.connecting ||
            _isProcessing;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Telegram',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth: 500,
          ),
          child: Padding(
            padding:
                const EdgeInsets.all(
              24,
            ),
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  24,
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                  children: [
                    Icon(
                      authenticated
                          ? Icons
                              .check_circle_outline
                          : Icons.telegram,
                      size: 72,
                    ),

                    const SizedBox(
                      height: 24,
                    ),

                    Text(
                      _title,
                      textAlign:
                          TextAlign.center,
                      style:
                          Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Text(
                      _description,
                      textAlign:
                          TextAlign.center,
                      style: _state ==
                              TelegramAuthState.error
                          ? TextStyle(
                              color:
                                  Theme.of(context)
                                      .colorScheme
                                      .error,
                            )
                          : null,
                    ),

                    const SizedBox(
                      height: 24,
                    ),

                    if (_showInput)
                      TextField(
                        controller:
                            _controller,
                        focusNode:
                            _focusNode,
                        keyboardType:
                            _keyboardType,
                        obscureText:
                            _obscureText,
                        enabled:
                            !loading,
                        decoration:
                            InputDecoration(
                          labelText:
                              _fieldLabel,
                          border:
                              const OutlineInputBorder(),
                        ),
                        onSubmitted:
                            (_) {
                          if (!loading) {
                            _onPressed();
                          }
                        },
                      ),

                    if (_showInput)
                      const SizedBox(
                        height: 16,
                      ),

                    if (!authenticated)
                      FilledButton.icon(
                        onPressed:
                            loading
                                ? null
                                : _onPressed,
                        icon: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth:
                                      2,
                                ),
                              )
                            : const Icon(
                                Icons
                                    .arrow_forward,
                              ),
                        label: Text(
                          _state ==
                                  TelegramAuthState
                                      .phoneRequired
                              ? 'Send Code'
                              : _state ==
                                      TelegramAuthState
                                          .codeRequired
                                  ? 'Confirm Code'
                                  : _state ==
                                          TelegramAuthState
                                              .passwordRequired
                                      ? 'Confirm Password'
                                      : 'Connect',
                        ),
                      ),

                    if (authenticated)
                      FilledButton.icon(
                        onPressed:
                            loading
                                ? null
                                : _openGroups,
                        icon: const Icon(
                          Icons
                              .groups_2_outlined,
                        ),
                        label: const Text(
                          'View Groups',
                        ),
                      ),

                    if (authenticated)
                      const SizedBox(
                        height: 12,
                      ),

                    if (authenticated)
                      OutlinedButton.icon(
                        onPressed:
                            loading
                                ? null
                                : _logout,
                        icon: const Icon(
                          Icons.logout,
                        ),
                        label: const Text(
                          'Disconnect Telegram',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}