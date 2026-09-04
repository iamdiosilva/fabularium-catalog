import 'package:flutter/material.dart';

import '../features/community/application/community_auth_service.dart';

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
                  'Sign in to your Fabularium account to start.',
                  textAlign:
                      TextAlign.center,
                ),
                const SizedBox(
                  height:
                      18,
                ),
                const _FlowIndicator(
                  activeStep:
                      1,
                ),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowIndicator
    extends StatelessWidget {
  final int activeStep;

  const _FlowIndicator({
    required this.activeStep,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      mainAxisAlignment:
          MainAxisAlignment.center,
      children:
          <Widget>[
        _Step(
          number:
              1,
          label:
              'Fabularium',
          active:
              activeStep ==
                  1,
          complete:
              activeStep >
                  1,
        ),
        Container(
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
        _Step(
          number:
              2,
          label:
              'Telegram',
          active:
              activeStep ==
                  2,
          complete:
              activeStep >
                  2,
        ),
      ],
    );
  }
}

class _Step
    extends StatelessWidget {
  final int number;
  final String label;
  final bool active;
  final bool complete;

  const _Step({
    required this.number,
    required this.label,
    required this.active,
    required this.complete,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final color =
        active ||
                complete
            ? Theme.of(
                context,
              )
                .colorScheme
                .primary
            : Theme.of(
                context,
              )
                .colorScheme
                .outline;

    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children:
          <Widget>[
        CircleAvatar(
          radius:
              15,
          backgroundColor:
              color,
          foregroundColor:
              Theme.of(
            context,
          )
                  .colorScheme
                  .onPrimary,
          child:
              complete
                  ? const Icon(
                      Icons.check,
                      size:
                          16,
                    )
                  : Text(
                      '$number',
                    ),
        ),
        const SizedBox(
          width:
              7,
        ),
        Text(
          label,
          style:
              TextStyle(
            fontWeight:
                active
                    ? FontWeight.bold
                    : FontWeight.normal,
            color:
                color,
          ),
        ),
      ],
    );
  }
}
