import 'package:flutter/material.dart';

import '../features/community/application/community_auth_service.dart';
import '../services/fabularium_session_service.dart';

enum _FabulariumAuthMode {
  signIn,
  signUp,
}

class FabulariumLoginPage
    extends StatefulWidget {
  const FabulariumLoginPage({
    super.key,
  });

  @override
  State<FabulariumLoginPage>
      createState() =>
          _FabulariumLoginPageState();
}

class _FabulariumLoginPageState
    extends State<FabulariumLoginPage> {
  final CommunityAuthService _auth =
      CommunityAuthService.instance;

  final FabulariumSessionService _session =
      FabulariumSessionService.instance;

  final TextEditingController _email =
      TextEditingController();

  final TextEditingController _password =
      TextEditingController();

  final TextEditingController
      _confirmPassword =
      TextEditingController();

  final TextEditingController _username =
      TextEditingController();

  final TextEditingController _displayName =
      TextEditingController();

  _FabulariumAuthMode _mode =
      _FabulariumAuthMode.signIn;

  bool _obscurePassword =
      true;

  bool _obscureConfirm =
      true;

  bool _changingAccount =
      false;

  String? _message;

  bool _messageIsError =
      false;

  @override
  void initState() {
    super.initState();

    _auth.addListener(
      _onAuthChanged,
    );
  }

  @override
  void dispose() {
    _auth.removeListener(
      _onAuthChanged,
    );

    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _username.dispose();
    _displayName.dispose();

    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _continueSavedAccount() async {
    if (!_auth.isSignedIn) {
      return;
    }

    _session
        .confirmFabulariumSession();
  }

  Future<void> _useAnotherAccount() async {
    if (_changingAccount) {
      return;
    }

    setState(() {
      _changingAccount =
          true;

      _message =
          null;
    });

    try {
      await _session
          .useAnotherFabulariumAccount();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message =
              error.toString();

          _messageIsError =
              true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _changingAccount =
              false;
        });
      }
    }
  }

  Future<void> _submit() async {
    FocusScope.of(
      context,
    ).unfocus();

    setState(() {
      _message =
          null;

      _messageIsError =
          false;
    });

    try {
      if (_mode ==
          _FabulariumAuthMode.signIn) {
        await _auth.signIn(
          email:
              _email.text,
          password:
              _password.text,
        );

        if (_auth.isSignedIn) {
          _session
              .confirmFabulariumSession();
        }

        return;
      }

      if (_password.text.length <
          8) {
        throw const CommunityAuthException(
          'Password must have at least 8 characters.',
        );
      }

      if (_password.text !=
          _confirmPassword.text) {
        throw const CommunityAuthException(
          'Passwords do not match.',
        );
      }

      final result =
          await _auth.signUp(
        email:
            _email.text,
        password:
            _password.text,
        username:
            _username.text,
        displayName:
            _displayName.text,
      );

      if (!mounted) {
        return;
      }

      if (result
          .needsEmailConfirmation) {
        setState(() {
          _mode =
              _FabulariumAuthMode.signIn;

          _message =
              'Account created. Confirm your email, then sign in to continue.';

          _messageIsError =
              false;
        });

        return;
      }

      if (_auth.isSignedIn) {
        _session
            .confirmFabulariumSession();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _message =
            error.toString();

        _messageIsError =
            true;
      });
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
                  520,
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
                      8,
                ),
                const Text(
                  'Start with your Fabularium account.',
                  textAlign:
                      TextAlign.center,
                ),
                const SizedBox(
                  height:
                      18,
                ),
                const _FlowIndicator(),
                const SizedBox(
                  height:
                      24,
                ),
                if (_auth.isSignedIn)
                  _buildSavedSessionCard()
                else
                  _buildAuthenticationCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSavedSessionCard() {
    final profile =
        _auth.profile;

    final label =
        profile?.displayName
                    .trim()
                    .isNotEmpty ==
                true
            ? profile!.displayName
            : _auth.email ??
                'Fabularium user';

    return Card(
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
              Icons.account_circle_outlined,
              size:
                  54,
            ),
            const SizedBox(
              height:
                  14,
            ),
            Text(
              'Welcome back',
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
            Text(
              label,
              textAlign:
                  TextAlign.center,
              style:
                  Theme.of(
                context,
              )
                      .textTheme
                      .titleMedium,
            ),
            if (_auth.email !=
                null) ...<Widget>[
              const SizedBox(
                height:
                    4,
              ),
              Text(
                _auth.email!,
                textAlign:
                    TextAlign.center,
                style:
                    Theme.of(
                  context,
                )
                        .textTheme
                        .bodySmall,
              ),
            ],
            const SizedBox(
              height:
                  24,
            ),
            FilledButton.icon(
              onPressed:
                  _changingAccount
                      ? null
                      : _continueSavedAccount,
              icon:
                  const Icon(
                Icons.arrow_forward,
              ),
              label:
                  const Text(
                'Continue',
              ),
            ),
            const SizedBox(
              height:
                  8,
            ),
            TextButton.icon(
              onPressed:
                  _changingAccount
                      ? null
                      : _useAnotherAccount,
              icon:
                  _changingAccount
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
                          Icons.switch_account_outlined,
                        ),
              label:
                  const Text(
                'Use another Fabularium account',
              ),
            ),
            if (_message !=
                null) ...<Widget>[
              const SizedBox(
                height:
                    12,
              ),
              Text(
                _message!,
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      _messageIsError
                          ? Theme.of(
                              context,
                            )
                              .colorScheme
                              .error
                          : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAuthenticationCard() {
    return Card(
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
            Text(
              _mode ==
                      _FabulariumAuthMode
                          .signIn
                  ? 'Fabularium Account'
                  : 'Create your account',
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
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(
              height:
                  20,
            ),
            SegmentedButton<
                _FabulariumAuthMode>(
              segments:
                  const <
                      ButtonSegment<
                          _FabulariumAuthMode>>[
                ButtonSegment<
                    _FabulariumAuthMode>(
                  value:
                      _FabulariumAuthMode
                          .signIn,
                  label:
                      Text(
                    'Sign In',
                  ),
                  icon:
                      Icon(
                    Icons.login,
                  ),
                ),
                ButtonSegment<
                    _FabulariumAuthMode>(
                  value:
                      _FabulariumAuthMode
                          .signUp,
                  label:
                      Text(
                    'Create Account',
                  ),
                  icon:
                      Icon(
                    Icons.person_add_alt_1,
                  ),
                ),
              ],
              selected:
                  <_FabulariumAuthMode>{
                _mode,
              },
              onSelectionChanged:
                  _auth.isLoading
                      ? null
                      : (
                          selection,
                        ) {
                          setState(
                            () {
                              _mode =
                                  selection.first;

                              _message =
                                  null;
                            },
                          );
                        },
            ),
            if (_mode ==
                _FabulariumAuthMode
                    .signUp) ...<Widget>[
              const SizedBox(
                height:
                    18,
              ),
              TextField(
                controller:
                    _username,
                enabled:
                    !_auth.isLoading,
                textInputAction:
                    TextInputAction.next,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Username',
                  prefixIcon:
                      Icon(
                    Icons.alternate_email,
                  ),
                  border:
                      OutlineInputBorder(),
                ),
              ),
              const SizedBox(
                height:
                    12,
              ),
              TextField(
                controller:
                    _displayName,
                enabled:
                    !_auth.isLoading,
                textInputAction:
                    TextInputAction.next,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Display name',
                  prefixIcon:
                      Icon(
                    Icons.badge_outlined,
                  ),
                  border:
                      OutlineInputBorder(),
                ),
              ),
            ] else
              const SizedBox(
                height:
                    18,
              ),
            const SizedBox(
              height:
                  12,
            ),
            TextField(
              controller:
                  _email,
              enabled:
                  !_auth.isLoading,
              keyboardType:
                  TextInputType.emailAddress,
              textInputAction:
                  TextInputAction.next,
              decoration:
                  const InputDecoration(
                labelText:
                    'Email',
                prefixIcon:
                    Icon(
                  Icons.email_outlined,
                ),
                border:
                    OutlineInputBorder(),
              ),
            ),
            const SizedBox(
              height:
                  12,
            ),
            TextField(
              controller:
                  _password,
              enabled:
                  !_auth.isLoading,
              obscureText:
                  _obscurePassword,
              onSubmitted:
                  (_) {
                if (_mode ==
                    _FabulariumAuthMode
                        .signIn) {
                  _submit();
                }
              },
              decoration:
                  InputDecoration(
                labelText:
                    'Password',
                prefixIcon:
                    const Icon(
                  Icons.lock_outline,
                ),
                suffixIcon:
                    IconButton(
                  onPressed:
                      () {
                    setState(
                      () {
                        _obscurePassword =
                            !_obscurePassword;
                      },
                    );
                  },
                  icon:
                      Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
                border:
                    const OutlineInputBorder(),
              ),
            ),
            if (_mode ==
                _FabulariumAuthMode
                    .signUp) ...<Widget>[
              const SizedBox(
                height:
                    12,
              ),
              TextField(
                controller:
                    _confirmPassword,
                enabled:
                    !_auth.isLoading,
                obscureText:
                    _obscureConfirm,
                onSubmitted:
                    (_) =>
                        _submit(),
                decoration:
                    InputDecoration(
                  labelText:
                      'Confirm password',
                  prefixIcon:
                      const Icon(
                    Icons.lock_outline,
                  ),
                  suffixIcon:
                      IconButton(
                    onPressed:
                        () {
                      setState(
                        () {
                          _obscureConfirm =
                              !_obscureConfirm;
                        },
                      );
                    },
                    icon:
                        Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  border:
                      const OutlineInputBorder(),
                ),
              ),
            ],
            if (_message !=
                null) ...<Widget>[
              const SizedBox(
                height:
                    16,
              ),
              Text(
                _message!,
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      _messageIsError
                          ? Theme.of(
                              context,
                            )
                              .colorScheme
                              .error
                          : Theme.of(
                              context,
                            )
                              .colorScheme
                              .primary,
                ),
              ),
            ],
            const SizedBox(
              height:
                  20,
            ),
            FilledButton.icon(
              onPressed:
                  _auth.isLoading
                      ? null
                      : _submit,
              icon:
                  _auth.isLoading
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
                      : Icon(
                          _mode ==
                                  _FabulariumAuthMode
                                      .signIn
                              ? Icons.login
                              : Icons.person_add,
                        ),
              label:
                  Text(
                _mode ==
                        _FabulariumAuthMode
                            .signIn
                    ? 'Continue'
                    : 'Create Account',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowIndicator
    extends StatelessWidget {
  const _FlowIndicator();

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
              const Text(
            '1',
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
            fontWeight:
                FontWeight.bold,
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
              Theme.of(
            context,
          )
                  .colorScheme
                  .surfaceContainerHighest,
          foregroundColor:
              Theme.of(
            context,
          )
                  .colorScheme
                  .outline,
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
                Theme.of(
              context,
            )
                    .colorScheme
                    .outline,
          ),
        ),
      ],
    );
  }
}
