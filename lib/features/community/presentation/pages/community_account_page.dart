import 'package:flutter/material.dart';

import '../../../../services/fabularium_session_service.dart';
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

class _CommunityAccountPageState
    extends State<CommunityAccountPage> {
  final CommunityAuthService _auth =
      CommunityAuthService.instance;

  final FabulariumSessionService _session =
      FabulariumSessionService.instance;

  bool _signingOut =
      false;

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

    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context:
          context,
      builder:
          (
        context,
      ) {
        return AlertDialog(
          title:
              const Text(
            'Sign out of Fabularium?',
          ),
          content:
              const Text(
            'This will sign out of both your Fabularium account and Telegram transfer session on this computer.',
          ),
          actions:
              <Widget>[
            TextButton(
              onPressed:
                  () =>
                      Navigator.of(
                context,
              ).pop(
                false,
              ),
              child:
                  const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed:
                  () =>
                      Navigator.of(
                context,
              ).pop(
                true,
              ),
              child:
                  const Text(
                'Sign Out',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed !=
        true) {
      return;
    }

    setState(() {
      _signingOut =
          true;
    });

    try {
      await _session.signOutAll();

      if (!mounted) {
        return;
      }

      Navigator.of(
        context,
      ).popUntil(
        (
          route,
        ) =>
            route.isFirst,
      );
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
          _signingOut =
              false;
        });
      }
    }
  }

  Future<void> _editProfile() async {
    final profile =
        _auth.profile;

    if (profile ==
        null) {
      return;
    }

    final usernameController =
        TextEditingController(
      text:
          profile.username,
    );

    final displayNameController =
        TextEditingController(
      text:
          profile.displayName,
    );

    final avatarController =
        TextEditingController(
      text:
          profile.avatarUrl ??
              '',
    );

    final bioController =
        TextEditingController(
      text:
          profile.bio ??
              '',
    );

    final result =
        await showDialog<
            _ProfileEditResult>(
      context:
          context,
      builder:
          (
        context,
      ) {
        return AlertDialog(
          title:
              const Text(
            'Edit Profile',
          ),
          content:
              SizedBox(
            width:
                520,
            child:
                SingleChildScrollView(
              child:
                  Column(
                mainAxisSize:
                    MainAxisSize.min,
                children:
                    <Widget>[
                  TextField(
                    controller:
                        usernameController,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Username',
                      helperText:
                          '3-24 lowercase letters, numbers or underscore',
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
                        displayNameController,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Display name',
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
                        avatarController,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Avatar URL (optional)',
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
                        bioController,
                    minLines:
                        3,
                    maxLines:
                        6,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Bio',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions:
              <Widget>[
            TextButton(
              onPressed:
                  () =>
                      Navigator.of(
                context,
              ).pop(),
              child:
                  const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed:
                  () {
                Navigator.of(
                  context,
                ).pop(
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
              child:
                  const Text(
                'Save',
              ),
            ),
          ],
        );
      },
    );

    usernameController.dispose();
    displayNameController.dispose();
    avatarController.dispose();
    bioController.dispose();

    if (result ==
        null) {
      return;
    }

    try {
      await _auth.updateProfile(
        username:
            result.username,
        displayName:
            result.displayName,
        avatarUrl:
            result.avatarUrl,
        bio:
            result.bio,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content:
              Text(
            'Profile updated.',
          ),
        ),
      );
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
      appBar:
          AppBar(
        title:
            const Text(
          'Fabularium Account',
        ),
      ),
      body:
          _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_auth.isSignedIn) {
      return const Center(
        child:
            Text(
          'Fabularium session ended.',
        ),
      );
    }

    final profile =
        _auth.profile;

    if (_auth.isLoading &&
        profile ==
            null) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    return ListView(
      padding:
          const EdgeInsets.all(
        28,
      ),
      children:
          <Widget>[
        ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth:
                900,
          ),
          child:
              Card(
            child:
                Padding(
              padding:
                  const EdgeInsets.all(
                24,
              ),
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children:
                    <Widget>[
                  Row(
                    children:
                        <Widget>[
                      CircleAvatar(
                        radius:
                            34,
                        child:
                            Text(
                          _initials(
                            profile,
                          ),
                          style:
                              const TextStyle(
                            fontSize:
                                20,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width:
                            18,
                      ),
                      Expanded(
                        child:
                            Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children:
                              <Widget>[
                            Text(
                              profile?.displayName ??
                                  _auth.email ??
                                  'Fabularium User',
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
                                  4,
                            ),
                            if (profile !=
                                null)
                              Text(
                                '@${profile.username}',
                              ),
                            if (_auth.email !=
                                null)
                              Text(
                                _auth.email!,
                                style:
                                    Theme.of(
                                  context,
                                )
                                        .textTheme
                                        .bodySmall,
                              ),
                          ],
                        ),
                      ),
                      Chip(
                        avatar:
                            Icon(
                          _auth.isAdmin
                              ? Icons.admin_panel_settings
                              : Icons.person_outline,
                          size:
                              18,
                        ),
                        label:
                            Text(
                          _auth.isAdmin
                              ? 'ADMIN'
                              : 'USER',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height:
                        24,
                  ),
                  if (profile !=
                      null)
                    _buildStats(
                      profile,
                    ),
                  const SizedBox(
                    height:
                        20,
                  ),
                  if (profile?.bio !=
                          null &&
                      profile!
                          .bio!
                          .isNotEmpty) ...<Widget>[
                    Text(
                      profile.bio!,
                    ),
                    const SizedBox(
                      height:
                          20,
                    ),
                  ],
                  const ListTile(
                    contentPadding:
                        EdgeInsets.zero,
                    leading:
                        Icon(
                      Icons.cloud_done_outlined,
                    ),
                    title:
                        Text(
                      'Telegram connected',
                    ),
                    subtitle:
                        Text(
                      'The transfer session is linked to this Fabularium session.',
                    ),
                  ),
                  const SizedBox(
                    height:
                        14,
                  ),
                  Wrap(
                    spacing:
                        10,
                    runSpacing:
                        10,
                    children:
                        <Widget>[
                      OutlinedButton.icon(
                        onPressed:
                            _auth.isLoading
                                ? null
                                : _editProfile,
                        icon:
                            const Icon(
                          Icons.edit_outlined,
                        ),
                        label:
                            const Text(
                          'Edit Profile',
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed:
                            () {
                          Navigator.of(
                            context,
                          ).push(
                            MaterialPageRoute(
                              builder:
                                  (_) =>
                                      const CommunityMySubmissionsPage(),
                            ),
                          );
                        },
                        icon:
                            const Icon(
                          Icons.upload_file_outlined,
                        ),
                        label:
                            const Text(
                          'My Submissions',
                        ),
                      ),
                      if (_auth.isAdmin)
                        FilledButton.icon(
                          onPressed:
                              () {
                            Navigator.of(
                              context,
                            ).push(
                              MaterialPageRoute(
                                builder:
                                    (_) =>
                                        const CommunityModerationPage(),
                              ),
                            );
                          },
                          icon:
                              const Icon(
                            Icons.fact_check_outlined,
                          ),
                          label:
                              const Text(
                            'Moderation',
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed:
                            _signingOut
                                ? null
                                : _signOut,
                        icon:
                            _signingOut
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
                                    Icons.logout,
                                  ),
                        label:
                            const Text(
                          'Sign Out',
                        ),
                      ),
                    ],
                  ),
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
      spacing:
          12,
      runSpacing:
          12,
      children:
          <Widget>[
        _StatCard(
          icon:
              Icons.stars_outlined,
          label:
              'Points',
          value:
              '${profile.points}',
        ),
        _StatCard(
          icon:
              Icons.shield_outlined,
          label:
              'Reputation',
          value:
              '${profile.reputation}',
        ),
        _StatCard(
          icon:
              Icons.workspace_premium_outlined,
          label:
              'Level',
          value:
              profile.level,
        ),
        _StatCard(
          icon:
              Icons.upload_file_outlined,
          label:
              'Approved uploads',
          value:
              '${profile.approvedUploads}',
        ),
        _StatCard(
          icon:
              Icons.favorite_outline,
          label:
              'Likes received',
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
        profile?.displayName
                    .trim()
                    .isNotEmpty ==
                true
            ? profile!
                .displayName
                .trim()
            : profile?.username ??
                _auth.email ??
                'F';

    final parts =
        source
            .split(
              RegExp(
                r'\s+',
              ),
            )
            .where(
              (
                part,
              ) =>
                  part.isNotEmpty,
            )
            .toList();

    if (parts.isEmpty) {
      return 'F';
    }

    if (parts.length ==
        1) {
      return parts.first
          .substring(
            0,
            1,
          )
          .toUpperCase();
    }

    return '${parts.first.substring(0, 1)}'
            '${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _StatCard
    extends StatelessWidget {
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
      width:
          164,
      padding:
          const EdgeInsets.all(
        14,
      ),
      decoration:
          BoxDecoration(
        border:
            Border.all(
          color:
              Theme.of(
            context,
          )
                  .dividerColor,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children:
            <Widget>[
          Icon(
            icon,
          ),
          const SizedBox(
            height:
                8,
          ),
          Text(
            value,
            maxLines:
                1,
            overflow:
                TextOverflow.ellipsis,
            style:
                Theme.of(
              context,
            )
                    .textTheme
                    .titleMedium
                    ?.copyWith(
                      fontWeight:
                          FontWeight.bold,
                    ),
          ),
          const SizedBox(
            height:
                2,
          ),
          Text(
            label,
            style:
                Theme.of(
              context,
            )
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
