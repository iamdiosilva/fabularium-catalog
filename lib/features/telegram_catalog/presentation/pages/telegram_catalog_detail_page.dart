import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../services/telegram_preview_manager.dart';
import '../../domain/entities/telegram_catalog_entry.dart';

class TelegramCatalogDetailPage
    extends StatefulWidget {
  final TelegramCatalogEntry entry;

  const TelegramCatalogDetailPage({
    super.key,
    required this.entry,
  });

  @override
  State<TelegramCatalogDetailPage>
      createState() =>
          _TelegramCatalogDetailPageState();
}

class _TelegramCatalogDetailPageState
    extends State<
        TelegramCatalogDetailPage> {
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
  Widget build(
    BuildContext context,
  ) {
    final entry = widget.entry;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          entry.name,
        ),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding:
                  const EdgeInsets.all(
                24,
              ),
              child:
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
                      fit: BoxFit.contain,
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
                      size: 90,
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView(
              padding:
                  const EdgeInsets.all(
                28,
              ),
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons
                          .cloud_done_outlined,
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Text(
                      'Telegram Catalog',
                      style:
                          Theme.of(
                        context,
                      )
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 18,
                ),
                Text(
                  entry.name,
                  style:
                      Theme.of(
                    context,
                  )
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                ),
                if (entry
                    .studio
                    .isNotEmpty) ...[
                  const SizedBox(
                    height: 6,
                  ),
                  Text(
                    entry.studio,
                    style:
                        Theme.of(
                      context,
                    )
                            .textTheme
                            .titleMedium,
                  ),
                ],
                const SizedBox(
                  height: 24,
                ),
                _info(
                  'Category',
                  entry.category,
                ),
                _info(
                  'Type',
                  entry.type,
                ),
                _info(
                  'Scale',
                  entry.scale,
                ),
                _info(
                  'Height',
                  entry.height,
                ),
                _info(
                  'Archive',
                  entry
                      .archiveSizeLabel,
                ),
                if (entry.partCount !=
                    null)
                  _info(
                    'Parts',
                    entry.partCount
                        .toString(),
                  ),
                if (entry.publishedAt !=
                    null)
                  _info(
                    'Published',
                    _formatDate(
                      entry.publishedAt!,
                    ),
                  ),
                const SizedBox(
                  height: 10,
                ),
                Text(
                  'Package ID',
                  style:
                      Theme.of(
                    context,
                  )
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                ),
                const SizedBox(
                  height: 5,
                ),
                SelectableText(
                  entry.packageId,
                ),
                if (entry
                    .description
                    .isNotEmpty) ...[
                  const SizedBox(
                    height: 24,
                  ),
                  Text(
                    'Description',
                    style:
                        Theme.of(
                      context,
                    )
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    entry.description,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(
    String label,
    String value,
  ) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(
    DateTime value,
  ) {
    final local = value.toLocal();

    String two(
      int number,
    ) =>
        number
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '${two(local.day)}/'
        '${two(local.month)}/'
        '${local.year} '
        '${two(local.hour)}:'
        '${two(local.minute)}';
  }
}
