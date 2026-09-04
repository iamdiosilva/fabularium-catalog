import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../services/community_package_download_service.dart';
import '../../../../services/telegram_file_service.dart';
import '../../application/community_auth_service.dart';
import '../../data/community_repository.dart';
import '../../domain/community_catalog_model.dart';

class CommunityCatalogDetailPage
    extends StatefulWidget {
  final CommunityCatalogModel model;

  const CommunityCatalogDetailPage({
    super.key,
    required this.model,
  });

  @override
  State<CommunityCatalogDetailPage>
      createState() =>
          _CommunityCatalogDetailPageState();
}

class _CommunityCatalogDetailPageState
    extends State<CommunityCatalogDetailPage> {
  final CommunityRepository _community =
      CommunityRepository.instance;

  final CommunityAuthService _auth =
      CommunityAuthService.instance;

  final CommunityPackageDownloadService _downloads =
      CommunityPackageDownloadService.instance;

  bool _liked =
      false;

  late int _likeCount;

  bool _likeBusy =
      false;

  bool _preparingDownload =
      false;

  @override
  void initState() {
    super.initState();

    _likeCount =
        widget.model.likeCount;

    unawaited(
      _loadLikeState(),
    );
  }

  Future<void> _loadLikeState() async {
    if (!_auth.isSignedIn) {
      return;
    }

    try {
      final liked =
          await _community.hasLikedModel(
        widget.model.modelId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _liked =
            liked;
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (!_auth.isSignedIn ||
        _likeBusy) {
      return;
    }

    setState(() {
      _likeBusy =
          true;
    });

    try {
      if (_liked) {
        await _community.unlikeModel(
          widget.model.modelId,
        );

        if (mounted) {
          setState(() {
            _liked =
                false;

            _likeCount =
                (_likeCount - 1)
                    .clamp(
                      0,
                      1 << 31,
                    )
                    .toInt();
          });
        }
      } else {
        await _community.likeModel(
          widget.model.modelId,
        );

        if (mounted) {
          setState(() {
            _liked =
                true;

            _likeCount++;
          });
        }
      }
    } catch (error) {
      if (mounted) {
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
    } finally {
      if (mounted) {
        setState(() {
          _likeBusy =
              false;
        });
      }
    }
  }

  Future<void> _download() async {
    if (_preparingDownload) {
      return;
    }

    setState(() {
      _preparingDownload =
          true;
    });

    try {
      final handle =
          await _downloads.startDownload(
        widget.model,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content:
              Text(
            '${handle.tasks.length} file part'
            '${handle.tasks.length == 1 ? '' : 's'} '
            'added to Downloads.',
          ),
        ),
      );

      unawaited(
        _watchDownloadCompletion(
          handle.completed,
        ),
      );
    } catch (error) {
      if (mounted) {
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
    } finally {
      if (mounted) {
        setState(() {
          _preparingDownload =
              false;
        });
      }
    }
  }

  Future<void> _watchDownloadCompletion(
    Future<String> completed,
  ) async {
    try {
      final path =
          await completed;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content:
              Text(
            'Download verified: '
            '${TelegramFileService.instance.sanitizeFileName(widget.model.name)}',
          ),
          action:
              SnackBarAction(
            label:
                'Show',
            onPressed:
                () =>
                    TelegramFileService.instance
                        .showFileInExplorer(
              path,
            ),
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
    final model =
        widget.model;

    return Scaffold(
      appBar:
          AppBar(
        title:
            Text(
          model.name,
        ),
      ),
      body:
          ListView(
        padding:
            const EdgeInsets.all(
          28,
        ),
        children:
            <Widget>[
          Center(
            child:
                ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth:
                    980,
              ),
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children:
                    <Widget>[
                  Container(
                    height:
                        220,
                    decoration:
                        BoxDecoration(
                      color:
                          Theme.of(
                        context,
                      )
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(
                        22,
                      ),
                    ),
                    child:
                        Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children:
                          <Widget>[
                        Icon(
                          Icons.view_in_ar_outlined,
                          size:
                              82,
                          color:
                              Theme.of(
                            context,
                          )
                                  .colorScheme
                                  .primary,
                        ),
                        const SizedBox(
                          height:
                              12,
                        ),
                        Text(
                          model.category ??
                              'Community Model',
                          style:
                              Theme.of(
                            context,
                          )
                                  .textTheme
                                  .titleMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height:
                        24,
                  ),
                  Text(
                    model.name,
                    style:
                        Theme.of(
                      context,
                    )
                            .textTheme
                            .displaySmall
                            ?.copyWith(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                  ),
                  const SizedBox(
                    height:
                        10,
                  ),
                  Text(
                    model.contributorLabel,
                    style:
                        Theme.of(
                      context,
                    )
                            .textTheme
                            .titleMedium,
                  ),
                  const SizedBox(
                    height:
                        22,
                  ),
                  Wrap(
                    spacing:
                        10,
                    runSpacing:
                        10,
                    children:
                        <Widget>[
                      _MetaChip(
                        label:
                            'Studio',
                        value:
                            model.studio,
                      ),
                      _MetaChip(
                        label:
                            'Category',
                        value:
                            model.category,
                      ),
                      _MetaChip(
                        label:
                            'Type',
                        value:
                            model.type,
                      ),
                      _MetaChip(
                        label:
                            'Scale',
                        value:
                            model.scale,
                      ),
                      _MetaChip(
                        label:
                            'Height',
                        value:
                            model.height,
                      ),
                      _MetaChip(
                        label:
                            'Archive',
                        value:
                            _formatBytes(
                          model.archiveSize,
                        ),
                      ),
                    ],
                  ),
                  if (model.description !=
                      null) ...<Widget>[
                    const SizedBox(
                      height:
                          26,
                    ),
                    Text(
                      'Description',
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
                      height:
                          8,
                    ),
                    Text(
                      model.description!,
                    ),
                  ],
                  if (model.tags.isNotEmpty) ...<Widget>[
                    const SizedBox(
                      height:
                          24,
                    ),
                    Wrap(
                      spacing:
                          8,
                      runSpacing:
                          8,
                      children:
                          model.tags
                              .map(
                                (
                                  tag,
                                ) =>
                                    Chip(
                                  label:
                                      Text(
                                    tag,
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ],
                  const SizedBox(
                    height:
                        30,
                  ),
                  Wrap(
                    spacing:
                        12,
                    runSpacing:
                        12,
                    children:
                        <Widget>[
                      FilledButton.icon(
                        onPressed:
                            _preparingDownload
                                ? null
                                : _download,
                        icon:
                            _preparingDownload
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
                                    Icons.download,
                                  ),
                        label:
                            const Text(
                          'Download',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _likeBusy
                                ? null
                                : _toggleLike,
                        icon:
                            Icon(
                          _liked
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                        label:
                            Text(
                          '$_likeCount',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height:
                        18,
                  ),
                  Text(
                    '${model.partCount} storage part'
                    '${model.partCount == 1 ? '' : 's'} · '
                    'Downloads are verified with SHA-256 after assembly.',
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
          ),
        ],
      ),
    );
  }

  String _formatBytes(
    int bytes,
  ) {
    if (bytes <=
        0) {
      return 'Unknown';
    }

    const mb =
        1024 * 1024;

    const gb =
        mb * 1024;

    if (bytes >=
        gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    if (bytes >=
        mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }

    return '$bytes B';
  }
}

class _MetaChip
    extends StatelessWidget {
  final String label;
  final String? value;

  const _MetaChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final text =
        value?.trim() ?? '';

    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Chip(
      label:
          Text(
        '$label: $text',
      ),
    );
  }
}
