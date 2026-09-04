import 'package:flutter/material.dart';

import '../../../../services/supabase_service.dart';
import '../../application/community_auth_service.dart';
import '../../domain/community_profile.dart';
import 'community_moderation_page.dart';
import 'community_my_submissions_page.dart';

class CommunityAccountPage
    extends StatefulWidget {
  const CommunityAccountPage({
    super.key,
  });

  @override
  State<CommunityAccountPage>
      createState() =>
          _CommunityAccountPageState();
}

enum _AuthMode {
  signIn,
  signUp,
}

class _CommunityAccountPageState
    extends State<CommunityAccountPage> {
  final CommunityAuthService _auth =
      CommunityAuthService.instance;

  final TextEditingController
      _emailController =
      TextEditingController();

  final TextEditingController
      _passwordController =
      TextEditingController();

  final TextEditingController
      _confirmPasswordController =
      TextEditingController();

  final TextEditingController
      _usernameController =
      TextEditingController();

  final TextEditingController
      _displayNameController =
      TextEditingController();

  _AuthMode _mode =
      _AuthMode.signIn;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();

    _auth.addListener(
      _onAuthChanged,
    );

    _auth.refresh();
  }

  @override
  void dispose() {
    _auth.removeListener(
      _onAuthChanged,
    );

    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();

    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _message = null;
      _messageIsError = false;
    });

    try {
      if (_mode == _AuthMode.signIn) {
        await _auth.signIn(
          email: _emailController.text,
          password:
              _passwordController.text,
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _message = 'Signed in successfully.';
        });

        return;
      }

      if (_passwordController.text.length <
          8) {
        throw const CommunityAuthException(
          'Password must have at least 8 characters.',
        );
      }

      if (_passwordController.text !=
          _confirmPasswordController.text) {
        throw const CommunityAuthException(
          'Passwords do not match.',
        );
      }

      final result = await _auth.signUp(
        email: _emailController.text,
        password:
            _passwordController.text,
        username:
            _usernameController.text,
        displayName:
            _displayNameController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _message = result.needsEmailConfirmation
            ? 'Account created. Check your email to confirm the account, then sign in.'
            : 'Account created and signed in.';
        _messageIsError = false;

        if (result.needsEmailConfirmation) {
          _mode = _AuthMode.signIn;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _message = error.toString();
        _messageIsError = true;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();

      if (!mounted) {
        return;
      }

      setState(() {
        _message = 'Signed out.';
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _message = error.toString();
        _messageIsError = true;
      });
    }
  }

  Future<void> _editProfile() async {
    final profile = _auth.profile;

    if (profile == null) {
      return;
    }

    final usernameController =
        TextEditingController(
      text: profile.username,
    );

    final displayNameController =
        TextEditingController(
      text: profile.displayName,
    );

    final avatarController =
        TextEditingController(
      text: profile.avatarUrl ?? '',
    );

    final bioController =
        TextEditingController(
      text: profile.bio ?? '',
    );

    final result =
        await showDialog<_ProfileEditResult>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Edit Profile',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller:
                        usernameController,
                    decoration:
                        const InputDecoration(
                      labelText: 'Username',
                      helperText:
                          '3-24 lowercase letters, numbers or underscore',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller:
                        displayNameController,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Display name',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller:
                        avatarController,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Avatar URL (optional)',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller:
                        bioController,
                    minLines: 3,
                    maxLines: 6,
                    decoration:
                        const InputDecoration(
                      labelText: 'Bio',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _ProfileEditResult(
                    username:
                        usernameController.text,
                    displayName:
                        displayNameController.text,
                    avatarUrl:
                        avatarController.text,
                    bio:
                        bioController.text,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    usernameController.dispose();
    displayNameController.dispose();
    avatarController.dispose();
    bioController.dispose();

    if (result == null) {
      return;
    }

    try {
      await _auth.updateProfile(
        username: result.username,
        displayName:
            result.displayName,
        avatarUrl: result.avatarUrl,
        bio: result.bio,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Profile updated.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
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
      appBar: AppBar(
        title: const Text(
          'Fabularium Account',
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!SupabaseService
        .instance.isConfigured) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Supabase is not configured. Start Fabularium with the local Supabase dart-define file.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!SupabaseService
        .instance.isInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Supabase initialization failed.\n${SupabaseService.instance.initializationError ?? ''}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_auth.isSignedIn) {
      return _buildSignedIn();
    }

    return _buildAuthForm();
  }

  Widget _buildAuthForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth: 480,
          ),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 52,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _mode == _AuthMode.signIn
                        ? 'Welcome to Fabularium'
                        : 'Create your Fabularium account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                          fontWeight:
                              FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mode == _AuthMode.signIn
                        ? 'Sign in to use the community features.'
                        : 'Your account will be used for submissions, likes, points and reputation.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<_AuthMode>(
                    segments: const [
                      ButtonSegment(
                        value: _AuthMode.signIn,
                        label: Text('Sign In'),
                        icon: Icon(
                          Icons.login,
                        ),
                      ),
                      ButtonSegment(
                        value: _AuthMode.signUp,
                        label: Text('Create Account'),
                        icon: Icon(
                          Icons.person_add_alt_1,
                        ),
                      ),
                    ],
                    selected: <_AuthMode>{
                      _mode,
                    },
                    onSelectionChanged:
                        _auth.isLoading
                            ? null
                            : (selection) {
                                setState(() {
                                  _mode = selection.first;
                                  _message = null;
                                });
                              },
                  ),
                  const SizedBox(height: 20),
                  if (_mode ==
                      _AuthMode.signUp) ...[
                    TextField(
                      controller:
                          _usernameController,
                      enabled:
                          !_auth.isLoading,
                      textInputAction:
                          TextInputAction.next,
                      decoration:
                          const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(
                          Icons.alternate_email,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller:
                          _displayNameController,
                      enabled:
                          !_auth.isLoading,
                      textInputAction:
                          TextInputAction.next,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Display name',
                        prefixIcon: Icon(
                          Icons.badge_outlined,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller:
                        _emailController,
                    enabled:
                        !_auth.isLoading,
                    keyboardType:
                        TextInputType.emailAddress,
                    textInputAction:
                        TextInputAction.next,
                    decoration:
                        const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(
                        Icons.email_outlined,
                      ),
                      border:
                          OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller:
                        _passwordController,
                    enabled:
                        !_auth.isLoading,
                    obscureText:
                        _obscurePassword,
                    onSubmitted: (_) {
                      if (_mode ==
                          _AuthMode.signIn) {
                        _submit();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                      ),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword =
                                !_obscurePassword;
                          });
                        },
                        icon: Icon(
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
                      _AuthMode.signUp) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller:
                          _confirmPasswordController,
                      enabled:
                          !_auth.isLoading,
                      obscureText:
                          _obscureConfirmPassword,
                      onSubmitted: (_) =>
                          _submit(),
                      decoration: InputDecoration(
                        labelText:
                            'Confirm password',
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                        ),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        border:
                            const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _messageIsError
                            ? Theme.of(context)
                                .colorScheme
                                .error
                            : Theme.of(context)
                                .colorScheme
                                .primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed:
                        _auth.isLoading
                            ? null
                            : _submit,
                    icon: _auth.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            _mode ==
                                    _AuthMode.signIn
                                ? Icons.login
                                : Icons.person_add,
                          ),
                    label: Text(
                      _mode == _AuthMode.signIn
                          ? 'Sign In'
                          : 'Create Account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignedIn() {
    final profile = _auth.profile;

    if (_auth.isLoading &&
        profile == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth: 900,
          ),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        child: Text(
                          _initials(profile),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.displayName ??
                                  _auth.email ??
                                  'Fabularium User',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            if (profile != null)
                              Text(
                                '@${profile.username}',
                              ),
                            if (_auth.email != null)
                              Text(
                                _auth.email!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                              ),
                          ],
                        ),
                      ),
                      Chip(
                        avatar: Icon(
                          _auth.isAdmin
                              ? Icons.admin_panel_settings
                              : Icons.person_outline,
                          size: 18,
                        ),
                        label: Text(
                          _auth.isAdmin
                              ? 'ADMIN'
                              : 'USER',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (profile != null)
                    _buildStats(profile),
                  const SizedBox(height: 20),
                  if (profile?.bio != null &&
                      profile!.bio!.isNotEmpty) ...[
                    Text(
                      profile.bio!,
                    ),
                    const SizedBox(height: 20),
                  ],
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            _auth.isLoading
                                ? null
                                : _editProfile,
                        icon: const Icon(
                          Icons.edit_outlined,
                        ),
                        label: const Text(
                          'Edit Profile',
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const CommunityMySubmissionsPage(),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.upload_file_outlined,
                        ),
                        label: const Text(
                          'My Submissions',
                        ),
                      ),
                      if (_auth.isAdmin)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context)
                                .push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const CommunityModerationPage(),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.fact_check_outlined,
                          ),
                          label: const Text(
                            'Moderation',
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed:
                            _auth.isLoading
                                ? null
                                : _signOut,
                        icon: const Icon(
                          Icons.logout,
                        ),
                        label: const Text(
                          'Sign Out',
                        ),
                      ),
                    ],
                  ),
                  if (_auth.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _auth.error.toString(),
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStats(
    CommunityProfile profile,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(
          icon: Icons.stars_outlined,
          label: 'Points',
          value: '${profile.points}',
        ),
        _StatCard(
          icon: Icons.shield_outlined,
          label: 'Reputation',
          value: '${profile.reputation}',
        ),
        _StatCard(
          icon: Icons.workspace_premium_outlined,
          label: 'Level',
          value: profile.level,
        ),
        _StatCard(
          icon: Icons.upload_file_outlined,
          label: 'Approved uploads',
          value:
              '${profile.approvedUploads}',
        ),
        _StatCard(
          icon: Icons.favorite_outline,
          label: 'Likes received',
          value:
              '${profile.likesReceived}',
        ),
      ],
    );
  }

  String _initials(
    CommunityProfile? profile,
  ) {
    final source =
        profile?.displayName.trim().isNotEmpty ==
                true
            ? profile!.displayName.trim()
            : profile?.username ??
                _auth.email ??
                'F';

    final parts = source
        .split(RegExp(r'\s+'))
        .where(
          (part) => part.isNotEmpty,
        )
        .toList();

    if (parts.isEmpty) {
      return 'F';
    }

    if (parts.length == 1) {
      return parts.first
          .substring(0, 1)
          .toUpperCase();
    }

    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: 164,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context)
              .dividerColor,
        ),
        borderRadius:
            BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(
                  fontWeight:
                      FontWeight.bold,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ProfileEditResult {
  final String username;
  final String displayName;
  final String avatarUrl;
  final String bio;

  const _ProfileEditResult({
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
  });
}
