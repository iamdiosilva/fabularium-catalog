import 'package:flutter/material.dart';

import '../../../../models/catalog_model.dart';
import '../../domain/entities/catalog_telegram_status.dart';

class CatalogModelCard extends StatelessWidget {
  final CatalogModel model;
  final String studioName;
  final bool showStudio;
  final VoidCallback? onTap;
  final String? actionLabel;
  final IconData actionIcon;
  final CatalogTelegramStatus? telegramStatus;

  const CatalogModelCard({
    super.key,
    required this.model,
    required this.studioName,
    this.showStudio = false,
    this.onTap,
    this.actionLabel,
    this.actionIcon = Icons.arrow_forward,
    this.telegramStatus,
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
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (preview != null)
                    Image.file(
                      preview,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                      errorBuilder:
                          (
                        context,
                        error,
                        stackTrace,
                      ) =>
                              const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 48,
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: 48,
                      ),
                    ),
                  if (telegramStatus != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _TelegramStatusBadge(
                        status: telegramStatus!,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(
                12,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (showStudio) ...[
                    const SizedBox(
                      height: 4,
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.business_outlined,
                          size: 14,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                        const SizedBox(
                          width: 4,
                        ),
                        Expanded(
                          child: Text(
                            studioName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(
                    height: 6,
                  ),
                  if (model.category.isNotEmpty)
                    Text(
                      model.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (model.type.isNotEmpty) ...[
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      _getTypeLabel(
                        model.type,
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(
                    height: 8,
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        size: 16,
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Text(
                        '${model.images.length}',
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      const Icon(
                        Icons.archive_outlined,
                        size: 16,
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Text(
                        '${model.archiveFiles.length}',
                      ),
                    ],
                  ),
                  if (telegramStatus != null) ...[
                    const SizedBox(
                      height: 9,
                    ),
                    _TelegramStatusLine(
                      status: telegramStatus!,
                    ),
                  ],
                  if (actionLabel != null &&
                      onTap != null) ...[
                    const SizedBox(
                      height: 12,
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: onTap,
                        icon: Icon(
                          actionIcon,
                        ),
                        label: Text(
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
    switch (type.toLowerCase()) {
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

class _TelegramStatusBadge
    extends StatelessWidget {
  final CatalogTelegramStatus status;

  const _TelegramStatusBadge({
    required this.status,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final colorScheme = Theme.of(
      context,
    ).colorScheme;

    final (
      icon,
      foreground,
      background,
      label,
    ) = switch (status.state) {
      CatalogTelegramSyncState.uploaded => (
          Icons.verified_outlined,
          colorScheme.onPrimaryContainer,
          colorScheme.primaryContainer,
          status.remoteVerified
              ? 'Verified'
              : 'Uploaded',
        ),
      CatalogTelegramSyncState.remoteMissing => (
          Icons.cloud_off_outlined,
          colorScheme.onErrorContainer,
          colorScheme.errorContainer,
          'Incomplete',
        ),
      CatalogTelegramSyncState.failed => (
          Icons.error_outline,
          colorScheme.onErrorContainer,
          colorScheme.errorContainer,
          'Failed',
        ),
      CatalogTelegramSyncState.uploading => (
          Icons.cloud_upload_outlined,
          colorScheme.onSecondaryContainer,
          colorScheme.secondaryContainer,
          'Uploading',
        ),
      CatalogTelegramSyncState.preparing => (
          Icons.inventory_2_outlined,
          colorScheme.onSecondaryContainer,
          colorScheme.secondaryContainer,
          'Preparing',
        ),
      CatalogTelegramSyncState.removing => (
          Icons.delete_sweep_outlined,
          colorScheme.onSecondaryContainer,
          colorScheme.secondaryContainer,
          'Removing',
        ),
      CatalogTelegramSyncState.verificationUnavailable => (
          Icons.cloud_queue_outlined,
          colorScheme.onTertiaryContainer,
          colorScheme.tertiaryContainer,
          'Unchecked',
        ),
      CatalogTelegramSyncState.checking => (
          Icons.sync,
          colorScheme.onSurfaceVariant,
          colorScheme.surfaceContainerHighest,
          'Checking',
        ),
      CatalogTelegramSyncState.notUploaded => (
          Icons.cloud_off_outlined,
          colorScheme.onSurfaceVariant,
          colorScheme.surfaceContainerHighest,
          'Not uploaded',
        ),
    };

    return Tooltip(
      message: status.detail ?? status.label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(
            999,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: foreground,
            ),
            const SizedBox(
              width: 5,
            ),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TelegramStatusLine
    extends StatelessWidget {
  final CatalogTelegramStatus status;

  const _TelegramStatusLine({
    required this.status,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final isError =
        status.state ==
                CatalogTelegramSyncState.failed ||
            status.state ==
                CatalogTelegramSyncState.remoteMissing;

    final isChecking =
        status.state ==
            CatalogTelegramSyncState.checking;

    return Row(
      children: [
        if (isChecking)
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          )
        else
          Icon(
            status.isUploaded
                ? Icons.cloud_done_outlined
                : isError
                    ? Icons.warning_amber_rounded
                    : status.isBusy
                        ? Icons.sync
                        : Icons.cloud_off_outlined,
            size: 15,
            color: isError
                ? Theme.of(
                    context,
                  ).colorScheme.error
                : null,
          ),
        const SizedBox(
          width: 5,
        ),
        Expanded(
          child: Text(
            status.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(
                  color: isError
                      ? Theme.of(
                          context,
                        ).colorScheme.error
                      : null,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
