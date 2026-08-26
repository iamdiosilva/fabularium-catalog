import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../services/telegram_preview_manager.dart';
import '../../domain/entities/telegram_catalog_entry.dart';

class TelegramCatalogCard
    extends StatefulWidget {
  final TelegramCatalogEntry entry;
  final VoidCallback onTap;

  const TelegramCatalogCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  State<TelegramCatalogCard> createState() =>
      _TelegramCatalogCardState();
}

class _TelegramCatalogCardState
    extends State<TelegramCatalogCard> {
  late Future<File?> _preview;

  @override
  void initState() {
    super.initState();
    _preview =
        TelegramPreviewManager.instance
            .getPreview(
      widget.entry.coverMedia,
    );
  }

  @override
  void didUpdateWidget(
    covariant TelegramCatalogCard
        oldWidget,
  ) {
    super.didUpdateWidget(
      oldWidget,
    );

    if (oldWidget.entry.coverMedia.cacheKey !=
        widget.entry.coverMedia.cacheKey) {
      _preview =
          TelegramPreviewManager.instance
              .getPreview(
        widget.entry.coverMedia,
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<File?>(
                    future: _preview,
                    builder:
                        (
                      context,
                      snapshot,
                    ) {
                      final file =
                          snapshot.data;

                      if (file != null) {
                        return Image.file(
                          file,
                          fit: BoxFit.cover,
                          cacheWidth: 700,
                        );
                      }

                      if (snapshot
                              .connectionState ==
                          ConnectionState
                              .waiting) {
                        return const Center(
                          child:
                              CircularProgressIndicator(),
                        );
                      }

                      return const Center(
                        child: Icon(
                          Icons
                              .cloud_outlined,
                          size: 54,
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            Theme.of(
                          context,
                        )
                                .colorScheme
                                .primaryContainer,
                        borderRadius:
                            BorderRadius
                                .circular(
                          999,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          Icon(
                            Icons
                                .cloud_done_outlined,
                            size: 14,
                          ),
                          SizedBox(
                            width: 4,
                          ),
                          Text(
                            'Telegram',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  FontWeight
                                      .w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.all(
                12,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.entry.name,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (widget
                      .entry
                      .studio
                      .isNotEmpty) ...[
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      widget.entry.studio,
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style:
                          Theme.of(
                        context,
                      )
                              .textTheme
                              .bodySmall,
                    ),
                  ],
                  if (widget
                          .entry
                          .category
                          .isNotEmpty ||
                      widget
                          .entry
                          .type
                          .isNotEmpty) ...[
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      <String>[
                        if (widget
                            .entry
                            .category
                            .isNotEmpty)
                          widget
                              .entry
                              .category,
                        if (widget
                            .entry
                            .type
                            .isNotEmpty)
                          widget
                              .entry
                              .type,
                      ].join(
                        ' · ',
                      ),
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                    ),
                  ],
                  if (widget
                          .entry
                          .scale
                          .isNotEmpty ||
                      widget
                          .entry
                          .height
                          .isNotEmpty) ...[
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      <String>[
                        if (widget
                            .entry
                            .scale
                            .isNotEmpty)
                          'Scale ${widget.entry.scale}',
                        if (widget
                            .entry
                            .height
                            .isNotEmpty)
                          widget
                              .entry
                              .height,
                      ].join(
                        ' · ',
                      ),
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style:
                          Theme.of(
                        context,
                      )
                              .textTheme
                              .bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
