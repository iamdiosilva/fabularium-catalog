import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../application/community_auth_service.dart';
import '../../application/community_submission_upload_service.dart';
import '../../data/community_repository.dart';

class CommunityNewSubmissionPage
    extends StatefulWidget {
  const CommunityNewSubmissionPage({
    super.key,
  });

  @override
  State<CommunityNewSubmissionPage>
      createState() =>
          _CommunityNewSubmissionPageState();
}

class _CommunityNewSubmissionPageState
    extends State<CommunityNewSubmissionPage> {
  final CommunityRepository _repository =
      CommunityRepository.instance;

  final CommunitySubmissionUploadService
      _upload =
      CommunitySubmissionUploadService.instance;

  final _nameController =
      TextEditingController();
  final _studioController =
      TextEditingController();
  final _categoryController =
      TextEditingController();
  final _typeController =
      TextEditingController();
  final _scaleController =
      TextEditingController();
  final _heightController =
      TextEditingController();
  final _descriptionController =
      TextEditingController();
  final _tagsController =
      TextEditingController();

  String? _filePath;
  int _fileSize = 0;

  bool _busy = false;
  double _progress = 0;
  int _sentBytes = 0;
  String? _stage;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _studioController.dispose();
    _categoryController.dispose();
    _typeController.dispose();
    _scaleController.dispose();
    _heightController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickArchive() async {
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

    final path =
        result?.files.single.path;

    if (path == null) {
      return;
    }

    final file =
        File(path);

    if (!await file.exists()) {
      return;
    }

    final size =
        await file.length();

    if (!mounted) {
      return;
    }

    setState(() {
      _filePath = path;
      _fileSize = size;
      _error = null;

      if (_nameController
          .text
          .trim()
          .isEmpty) {
        _nameController.text =
            p.basenameWithoutExtension(
          path,
        );
      }
    });
  }

  Future<void> _submit() async {
    if (!CommunityAuthService
        .instance.isSignedIn) {
      setState(() {
        _error =
            'Sign in before creating a submission.';
      });
      return;
    }

    final filePath =
        _filePath;

    if (filePath == null) {
      setState(() {
        _error =
            'Select a ZIP, RAR or 7Z archive.';
      });
      return;
    }

    final name =
        _nameController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _error =
            'Model name is required.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0;
      _sentBytes = 0;
      _stage =
          'Creating submission...';
      _error = null;
    });

    try {
      final submissionId =
          await _repository
              .createSubmission(
        payload:
            <String, dynamic>{
          'name':
              name,
          'studio':
              _nullable(
            _studioController.text,
          ),
          'category':
              _nullable(
            _categoryController.text,
          ),
          'type':
              _nullable(
            _typeController.text,
          ),
          'scale':
              _nullable(
            _scaleController.text,
          ),
          'height':
              _nullable(
            _heightController.text,
          ),
          'description':
              _nullable(
            _descriptionController.text,
          ),
          'tags':
              _readTags(
            _tagsController.text,
          ),
          'archiveFileName':
              p.basename(
            filePath,
          ),
          'archiveSize':
              _fileSize,
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _stage =
            'Uploading to Fabularium Worker...';
      });

      await _upload.uploadArchive(
        submissionId:
            submissionId,
        filePath:
            filePath,
        onProgress:
            (
          progress,
          sentBytes,
          totalBytes,
        ) {
          if (!mounted) {
            return;
          }

          setState(() {
            _progress =
                progress;
            _sentBytes =
                sentBytes;
          });
        },
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Upload received by the Fabularium Worker.',
          ),
        ),
      );

      Navigator.of(
        context,
      ).pop(
        true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            error.toString();
        _stage =
            'Upload failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'New Submission',
        ),
      ),
      body:
          ListView(
        padding:
            const EdgeInsets.all(
          24,
        ),
        children: [
          ConstrainedBox(
            constraints:
                const BoxConstraints(
              maxWidth: 820,
            ),
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  22,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                  children: [
                    Text(
                      'Model Archive',
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
                    const SizedBox(
                      height: 8,
                    ),
                    const Text(
                      'The archive is sent to the Fabularium Worker. '
                      'It is not stored in Supabase.',
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _busy
                              ? null
                              : _pickArchive,
                      icon:
                          const Icon(
                        Icons
                            .folder_zip_outlined,
                      ),
                      label:
                          const Text(
                        'Select Archive',
                      ),
                    ),
                    if (_filePath !=
                        null) ...[
                      const SizedBox(
                        height: 12,
                      ),
                      Text(
                        p.basename(
                          _filePath!,
                        ),
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatBytes(
                          _fileSize,
                        ),
                      ),
                    ],
                    const SizedBox(
                      height: 24,
                    ),
                    _field(
                      _nameController,
                      'Model name',
                      required:
                          true,
                    ),
                    _field(
                      _studioController,
                      'Studio',
                    ),
                    _field(
                      _categoryController,
                      'Category',
                    ),
                    _field(
                      _typeController,
                      'Type',
                    ),
                    _field(
                      _scaleController,
                      'Scale',
                    ),
                    _field(
                      _heightController,
                      'Height',
                    ),
                    TextField(
                      controller:
                          _descriptionController,
                      enabled:
                          !_busy,
                      minLines:
                          3,
                      maxLines:
                          7,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Description',
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    TextField(
                      controller:
                          _tagsController,
                      enabled:
                          !_busy,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Tags',
                        helperText:
                            'Comma-separated',
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    if (_stage !=
                        null) ...[
                      const SizedBox(
                        height: 20,
                      ),
                      Text(
                        _stage!,
                      ),
                    ],
                    if (_busy &&
                        _stage?.contains(
                              'Uploading',
                            ) ==
                            true) ...[
                      const SizedBox(
                        height: 8,
                      ),
                      LinearProgressIndicator(
                        value:
                            _progress,
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      Text(
                        '${(_progress * 100).toStringAsFixed(1)}% · '
                        '${_formatBytes(_sentBytes)} / ${_formatBytes(_fileSize)}',
                      ),
                    ],
                    if (_error !=
                        null) ...[
                      const SizedBox(
                        height: 16,
                      ),
                      Text(
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
                    ],
                    const SizedBox(
                      height: 22,
                    ),
                    FilledButton.icon(
                      onPressed:
                          _busy
                              ? null
                              : _submit,
                      icon:
                          _busy
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
                                      .cloud_upload_outlined,
                                ),
                      label:
                          const Text(
                        'Submit Archive',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
  }) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 12,
      ),
      child: TextField(
        controller:
            controller,
        enabled:
            !_busy,
        decoration:
            InputDecoration(
          labelText:
              required
                  ? '$label *'
                  : label,
          border:
              const OutlineInputBorder(),
        ),
      ),
    );
  }

  String? _nullable(
    String value,
  ) {
    final text =
        value.trim();

    return text.isEmpty
        ? null
        : text;
  }

  List<String> _readTags(
    String value,
  ) {
    return value
        .split(',')
        .map(
          (tag) =>
              tag.trim(),
        )
        .where(
          (tag) =>
              tag.isNotEmpty,
        )
        .toSet()
        .toList();
  }

  String _formatBytes(
    int bytes,
  ) {
    const kb =
        1024;
    const mb =
        kb * 1024;
    const gb =
        mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    }

    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(2)} KB';
    }

    return '$bytes B';
  }
}
