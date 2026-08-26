import 'package:flutter/material.dart';

import '../models/catalog_model.dart';

class CatalogModelCard
    extends StatelessWidget {
  final CatalogModel model;

  final String studioName;

  final bool showStudio;

  final VoidCallback? onTap;

  final String? actionLabel;

  final IconData actionIcon;

  const CatalogModelCard({
    super.key,
    required this.model,
    required this.studioName,
    this.showStudio = false,
    this.onTap,
    this.actionLabel,
    this.actionIcon =
        Icons.arrow_forward,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final preview =
        model.images.isNotEmpty
            ? model.images.first
            : null;

    return Card(
      clipBehavior:
          Clip.antiAlias,
      elevation:
          3,
      child:
          InkWell(
        onTap:
            onTap,
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child:
                  preview != null
                      ? Image.file(
                          preview,
                          fit:
                              BoxFit.cover,
                          cacheWidth:
                              600,
                          errorBuilder:
                              (
                            context,
                            error,
                            stackTrace,
                          ) {
                            return const Center(
                              child:
                                  Icon(
                                Icons.broken_image_outlined,
                                size:
                                    48,
                              ),
                            );
                          },
                        )
                      : const Center(
                          child:
                              Icon(
                            Icons.image_outlined,
                            size:
                                48,
                          ),
                        ),
            ),
            Padding(
              padding:
                  const EdgeInsets.all(
                12,
              ),
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    maxLines:
                        2,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize:
                          16,
                    ),
                  ),
                  if (showStudio) ...[
                    const SizedBox(
                      height:
                          4,
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.business_outlined,
                          size:
                              14,
                          color:
                              Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                        const SizedBox(
                          width:
                              4,
                        ),
                        Expanded(
                          child:
                              Text(
                            studioName,
                            maxLines:
                                1,
                            overflow:
                                TextOverflow.ellipsis,
                            style:
                                Theme.of(
                              context,
                            ).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(
                    height:
                        6,
                  ),
                  if (model.category
                      .isNotEmpty)
                    Text(
                      model.category,
                      maxLines:
                          1,
                      overflow:
                          TextOverflow.ellipsis,
                    ),
                  if (model.type
                      .isNotEmpty) ...[
                    const SizedBox(
                      height:
                          4,
                    ),
                    Text(
                      _getTypeLabel(
                        model.type,
                      ),
                      style:
                          Theme.of(
                        context,
                      ).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(
                    height:
                        8,
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        size:
                            16,
                      ),
                      const SizedBox(
                        width:
                            4,
                      ),
                      Text(
                        '${model.images.length}',
                      ),
                      const SizedBox(
                        width:
                            12,
                      ),
                      const Icon(
                        Icons.archive_outlined,
                        size:
                            16,
                      ),
                      const SizedBox(
                        width:
                            4,
                      ),
                      Text(
                        '${model.archiveFiles.length}',
                      ),
                    ],
                  ),
                  if (actionLabel !=
                          null &&
                      onTap !=
                          null) ...[
                    const SizedBox(
                      height:
                          12,
                    ),
                    SizedBox(
                      width:
                          double.infinity,
                      child:
                          FilledButton.tonalIcon(
                        onPressed:
                            onTap,
                        icon:
                            Icon(
                          actionIcon,
                        ),
                        label:
                            Text(
                          actionLabel!,
                        ),
                      ),
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

  String _getTypeLabel(
    String type,
  ) {
    switch (
        type.toLowerCase()) {
      case 'statue':
        return 'Statue';

      case 'bust':
        return 'Bust';

      case 'miniature':
        return 'Miniature';

      case 'diorama':
        return 'Diorama';

      default:
        return type;
    }
  }
}
