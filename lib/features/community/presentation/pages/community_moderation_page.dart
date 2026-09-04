import 'package:flutter/material.dart';

import '../../application/community_auth_service.dart';
import '../../data/community_repository.dart';
import '../../domain/community_submission.dart';

class CommunityModerationPage
    extends StatefulWidget {
  const CommunityModerationPage({
    super.key,
  });

  @override
  State<CommunityModerationPage>
      createState() =>
          _CommunityModerationPageState();
}

class _CommunityModerationPageState
    extends State<CommunityModerationPage> {
  final CommunityRepository _repository =
      CommunityRepository.instance;

  bool _isLoading = true;
  String? _error;
  List<CommunitySubmission> _submissions =
      const <CommunitySubmission>[];
  final Set<String> _busyIds =
      <String>{};

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    if (!CommunityAuthService
        .instance.isAdmin) {
      setState(() {
        _isLoading = false;
        _error =
            'Administrator access is required.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final submissions =
          await _repository
              .loadModerationQueue();

      if (!mounted) {
        return;
      }

      setState(() {
        _submissions = submissions;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _analyze(
    CommunitySubmission submission,
  ) async {
    await _runAction(
      submission,
      () => _repository
          .analyzeSubmission(
        submission.id,
      ),
      successMessage:
          'Duplicate analysis completed.',
    );
  }

  Future<void> _approve(
    CommunitySubmission submission,
  ) async {
    final note = await _askNote(
      title: 'Approve Submission',
      label: 'Review note (optional)',
    );

    if (note == null) {
      return;
    }

    await _runAction(
      submission,
      () => _repository.reviewSubmission(
        submissionId: submission.id,
        decision: 'approve',
        note: note,
      ),
      successMessage:
          'Submission approved.',
    );
  }

  Future<void> _reject(
    CommunitySubmission submission,
  ) async {
    final note = await _askNote(
      title: 'Reject Submission',
      label: 'Reason for rejection',
      required: true,
    );

    if (note == null) {
      return;
    }

    await _runAction(
      submission,
      () => _repository.reviewSubmission(
        submissionId: submission.id,
        decision: 'reject',
        note: note,
      ),
      successMessage:
          'Submission rejected.',
    );
  }

  Future<void> _markDuplicate(
    CommunitySubmission submission,
  ) async {
    final result = await _askDuplicate();

    if (result == null) {
      return;
    }

    await _runAction(
      submission,
      () => _repository.reviewSubmission(
        submissionId: submission.id,
        decision: 'duplicate',
        note: result.note,
        duplicateOfModelId:
            result.modelId,
      ),
      successMessage:
          'Submission marked as duplicate.',
    );
  }

  Future<void> _runAction(
    CommunitySubmission submission,
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    setState(() {
      _busyIds.add(submission.id);
    });

    try {
      await action();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            successMessage,
          ),
        ),
      );

      await _load();
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
    } finally {
      if (mounted) {
        setState(() {
          _busyIds.remove(
            submission.id,
          );
        });
      }
    }
  }

  Future<String?> _askNote({
    required String title,
    required String label,
    bool required = false,
  }) async {
    final controller =
        TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: label,
              border:
                  const OutlineInputBorder(),
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
                final value =
                    controller.text.trim();

                if (required &&
                    value.isEmpty) {
                  return;
                }

                Navigator.of(context).pop(
                  value,
                );
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    return result;
  }

  Future<_DuplicateDecision?>
      _askDuplicate() async {
    final modelController =
        TextEditingController();
    final noteController =
        TextEditingController();

    final result =
        await showDialog<_DuplicateDecision>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Mark as Duplicate',
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller:
                      modelController,
                  autofocus: true,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Existing modelId',
                    border:
                        OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller:
                      noteController,
                  minLines: 2,
                  maxLines: 5,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Review note (optional)',
                    border:
                        OutlineInputBorder(),
                  ),
                ),
              ],
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
                final modelId =
                    modelController.text.trim();

                if (modelId.isEmpty) {
                  return;
                }

                Navigator.of(context).pop(
                  _DuplicateDecision(
                    modelId: modelId,
                    note:
                        noteController.text.trim(),
                  ),
                );
              },
              child: const Text(
                'Mark Duplicate',
              ),
            ),
          ],
        );
      },
    );

    modelController.dispose();
    noteController.dispose();

    return result;
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Community Moderation',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                _isLoading ? null : _load,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings_outlined,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_submissions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 72,
            ),
            SizedBox(height: 16),
            Text(
              'No submissions waiting for moderation.',
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _submissions.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return _buildSubmissionCard(
          _submissions[index],
        );
      },
    );
  }

  Widget _buildSubmissionCard(
    CommunitySubmission submission,
  ) {
    final busy =
        _busyIds.contains(submission.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    submission.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                          fontWeight:
                              FontWeight.bold,
                        ),
                  ),
                ),
                _StatusChip(
                  value: submission.status,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Info(
                  label: 'Studio',
                  value:
                      submission.studio ?? '-',
                ),
                _Info(
                  label: 'Scale',
                  value:
                      submission.scale ?? '-',
                ),
                _Info(
                  label: 'Archive',
                  value:
                      _formatBytes(
                    submission.archiveSize,
                  ),
                ),
                _Info(
                  label: 'Duplicate',
                  value:
                      submission.duplicateStatus,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              'Submission: ${submission.id}\n'
              'Uploader: ${submission.submittedBy}\n'
              'SHA-256: ${submission.archiveSha256 ?? '-'}\n'
              'Fingerprint: ${submission.contentFingerprint ?? '-'}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall,
            ),
            if (submission
                    .duplicateOfModelId !=
                null) ...[
              const SizedBox(height: 8),
              Text(
                'Duplicate of: ${submission.duplicateOfModelId}',
              ),
            ],
            const SizedBox(height: 16),
            if (busy)
              const LinearProgressIndicator()
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        _analyze(submission),
                    icon: const Icon(
                      Icons.manage_search,
                    ),
                    label: const Text(
                      'Analyze Duplicates',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () =>
                        _approve(submission),
                    icon: const Icon(
                      Icons.check,
                    ),
                    label: const Text(
                      'Approve',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _markDuplicate(
                      submission,
                    ),
                    icon: const Icon(
                      Icons.content_copy,
                    ),
                    label: const Text(
                      'Duplicate',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _reject(submission),
                    icon: const Icon(
                      Icons.close,
                    ),
                    label: const Text(
                      'Reject',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(
    int bytes,
  ) {
    if (bytes <= 0) {
      return '-';
    }

    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }

    return '$bytes bytes';
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;

  const _Info({
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Text(
      '$label: $value',
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String value;

  const _StatusChip({
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Chip(
      label: Text(
        value
            .replaceAll('_', ' ')
            .toUpperCase(),
      ),
    );
  }
}

class _DuplicateDecision {
  final String modelId;
  final String note;

  const _DuplicateDecision({
    required this.modelId,
    required this.note,
  });
}
