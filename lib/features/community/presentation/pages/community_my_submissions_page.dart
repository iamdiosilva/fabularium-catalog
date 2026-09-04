import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../application/community_submission_upload_service.dart';
import '../../data/community_repository.dart';
import '../../domain/community_submission.dart';
import 'community_new_submission_page.dart';

class CommunityMySubmissionsPage
    extends StatefulWidget {
  const CommunityMySubmissionsPage({
    super.key,
  });

  @override
  State<CommunityMySubmissionsPage>
      createState() =>
          _CommunityMySubmissionsPageState();
}

class _CommunityMySubmissionsPageState
    extends State<CommunityMySubmissionsPage> {
  final CommunityRepository _repository =
      CommunityRepository.instance;

  final CommunitySubmissionUploadService
      _upload =
      CommunitySubmissionUploadService.instance;

  bool _loading = true;
  String? _error;

  List<CommunitySubmission>
      _submissions =
      const <CommunitySubmission>[];

  final Set<String> _busy =
      <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final submissions =
          await _repository
              .loadMySubmissions();

      if (!mounted) {
        return;
      }

      setState(() {
        _submissions =
            submissions;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final changed =
        await Navigator.of(
      context,
    ).push<bool>(
      MaterialPageRoute(
        builder:
            (_) =>
                const CommunityNewSubmissionPage(),
      ),
    );

    if (changed == true) {
      await _load();
    }
  }

  Future<void> _retry(
    CommunitySubmission submission,
  ) async {
    final result =
        await FilePicker.platform
            .pickFiles(
      type:
          FileType.custom,
      allowedExtensions:
          const <String>[
        'zip',
        'rar',
        '7z',
      ],
      allowMultiple:
          false,
    );

    final filePath =
        result?.files.single.path;

    if (filePath == null) {
      return;
    }

    final file =
        File(filePath);

    if (!await file.exists()) {
      return;
    }

    final size =
        await file.length();

    if (submission.archiveSize >
            0 &&
        submission.archiveSize !=
            size) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Retry requires the same archive size as the original submission.',
          ),
        ),
      );

      return;
    }

    if (submission.archiveFileName !=
            null &&
        submission.archiveFileName!
            .isNotEmpty &&
        submission.archiveFileName !=
            p.basename(filePath)) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Retry requires the same archive file name.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _busy.add(
        submission.id,
      );
    });

    try {
      await _upload.uploadArchive(
        submissionId:
            submission.id,
        filePath:
            filePath,
      );

      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            error.toString(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(
            submission.id,
          );
        });
      }
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
          'My Submissions',
        ),
        actions: [
          IconButton(
            tooltip:
                'Refresh',
            onPressed:
                _loading
                    ? null
                    : _load,
            icon:
                const Icon(
              Icons.refresh,
            ),
          ),
          IconButton(
            tooltip:
                'New Submission',
            onPressed:
                _create,
            icon:
                const Icon(
              Icons.add,
            ),
          ),
        ],
      ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed:
            _create,
        icon:
            const Icon(
          Icons.upload_file_outlined,
        ),
        label:
            const Text(
          'New Submission',
        ),
      ),
      body:
          _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.all(
            24,
          ),
          child: Text(
            _error!,
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
        ),
      );
    }

    if (_submissions.isEmpty) {
      return Center(
        child:
            FilledButton.icon(
          onPressed:
              _create,
          icon:
              const Icon(
            Icons.upload_file_outlined,
          ),
          label:
              const Text(
            'Create your first submission',
          ),
        ),
      );
    }

    return ListView.separated(
      padding:
          const EdgeInsets.fromLTRB(
        24,
        24,
        24,
        100,
      ),
      itemCount:
          _submissions.length,
      separatorBuilder:
          (_, _) =>
              const SizedBox(
        height: 14,
      ),
      itemBuilder:
          (
        context,
        index,
      ) {
        return _card(
          _submissions[index],
        );
      },
    );
  }

  Widget _card(
    CommunitySubmission submission,
  ) {
    final busy =
        _busy.contains(
      submission.id,
    );

    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          18,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    submission.name,
                    style:
                        Theme.of(
                      context,
                    )
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                  ),
                ),
                _statusChip(
                  submission,
                ),
              ],
            ),
            const SizedBox(
              height: 10,
            ),
            if (submission
                    .archiveFileName !=
                null)
              Text(
                submission
                    .archiveFileName!,
              ),
            if (submission
                    .archiveSize >
                0)
              Text(
                _formatBytes(
                  submission
                      .archiveSize,
                ),
              ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Submitted ${_formatDate(submission.submittedAt)}',
              style:
                  Theme.of(
                context,
              )
                      .textTheme
                      .bodySmall,
            ),
            if (submission
                    .uploadError !=
                null) ...[
              const SizedBox(
                height: 10,
              ),
              Text(
                submission
                    .uploadError!,
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
            ],
            if (submission
                    .reviewNote !=
                null) ...[
              const SizedBox(
                height: 10,
              ),
              Text(
                'Review: ${submission.reviewNote}',
              ),
            ],
            if (submission
                .canRetryUpload) ...[
              const SizedBox(
                height: 14,
              ),
              OutlinedButton.icon(
                onPressed:
                    busy
                        ? null
                        : () =>
                            _retry(
                          submission,
                        ),
                icon:
                    busy
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
                            Icons
                                .restart_alt,
                          ),
                label:
                    const Text(
                  'Retry Upload',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(
    CommunitySubmission submission,
  ) {
    final label =
        submission.status
            .replaceAll(
              '_',
              ' ',
            )
            .toUpperCase();

    final icon =
        switch (submission.status) {
      'uploading' =>
        Icons.cloud_upload_outlined,
      'uploaded' =>
        Icons.cloud_done_outlined,
      'processing' =>
        Icons.settings_outlined,
      'pending_review' =>
        Icons.hourglass_top_outlined,
      'duplicate_suspected' =>
        Icons.content_copy_outlined,
      'approved' =>
        Icons.thumb_up_alt_outlined,
      'publishing' =>
        Icons.publish_outlined,
      'published' =>
        Icons.verified_outlined,
      'rejected' =>
        Icons.block_outlined,
      'failed' =>
        Icons.error_outline,
      _ =>
        Icons.info_outline,
    };

    return Chip(
      avatar:
          Icon(
        icon,
        size:
            17,
      ),
      label:
          Text(
        label,
      ),
    );
  }

  String _formatDate(
    DateTime value,
  ) {
    final local =
        value.toLocal();

    final day =
        local.day
            .toString()
            .padLeft(
              2,
              '0',
            );

    final month =
        local.month
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$day/$month/${local.year}';
  }

  String _formatBytes(
    int bytes,
  ) {
    const mb =
        1024 * 1024;
    const gb =
        mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    return '${(bytes / mb).toStringAsFixed(2)} MB';
  }
}
