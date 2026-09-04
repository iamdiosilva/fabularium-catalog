import 'dart:async';

import 'package:flutter/material.dart';

import '../services/telegram_service.dart';

class DownloadAccessPage extends StatefulWidget {
  final bool returnOnSuccess;

  const DownloadAccessPage({
    super.key,
    this.returnOnSuccess = false,
  });

  @override
  State<DownloadAccessPage> createState() => _DownloadAccessPageState();
}

class _DownloadAccessPageState extends State<DownloadAccessPage> {
  final TelegramService _telegram = TelegramService.instance;
  final TextEditingController _phone = TextEditingController(text: '+55');
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();

  StreamSubscription<TelegramAuthState>? _subscription;
  bool _successWasReturned = false;

  @override
  void initState() {
    super.initState();

    _subscription = _telegram.stateStream.listen((_) {
      if (!mounted) return;
      setState(() {});
      _returnIfReady();
    });

    unawaited(_telegram.connect());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  void _returnIfReady() {
    if (!widget.returnOnSuccess ||
        _successWasReturned ||
        !_telegram.isAuthenticated ||
        !mounted) {
      return;
    }

    _successWasReturned = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Download Access')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Icon(Icons.cloud_download_outlined, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      'Connect downloads',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Fabularium uses your Telegram account only as the transfer network for large community files. '
                      'You do not need to browse channels, join the storage channel, or open Telegram while downloading.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    _buildState(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildState() {
    switch (_telegram.state) {
      case TelegramAuthState.connecting:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Checking your download connection...'),
            ],
          ),
        );

      case TelegramAuthState.phoneRequired:
      case TelegramAuthState.disconnected:
        return _form(
          title: 'Phone number',
          controller: _phone,
          button: 'Send Verification Code',
          icon: Icons.phone_outlined,
          onSubmit: () => _telegram.sendCode(_phone.text),
        );

      case TelegramAuthState.codeRequired:
        return _form(
          title: 'Verification code',
          controller: _code,
          button: 'Continue',
          icon: Icons.password_outlined,
          onSubmit: () => _telegram.signIn(_code.text),
        );

      case TelegramAuthState.passwordRequired:
        return _form(
          title: 'Two-step verification password',
          controller: _password,
          button: 'Continue',
          icon: Icons.lock_outline,
          obscure: true,
          onSubmit: () => _telegram.checkPassword(_password.text),
        );

      case TelegramAuthState.authenticated:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Icons.check)),
              title: Text(
                'Download Access connected',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Community downloads can now transfer directly to this computer.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.done),
              label: const Text('Done'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                await _telegram.logout();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect Download Access'),
            ),
          ],
        );

      case TelegramAuthState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _telegram.errorMessage ?? 'Download connection error.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _telegram.connect,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          obscureText: obscure,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            labelText: title,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onSubmit, child: Text(button)),
      ],
    );
  }
}
