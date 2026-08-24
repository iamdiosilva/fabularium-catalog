import 'package:flutter/material.dart';

import '../pages/download_queue_page.dart';
import '../services/download_queue_service.dart';

class DownloadQueueButton
    extends StatelessWidget {
  const DownloadQueueButton({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final queue =
        DownloadQueueService.instance;

    return AnimatedBuilder(
      animation:
          queue,
      builder:
          (
        context,
        child,
      ) {
        final count =
            queue.activeCount;

        return IconButton(
          tooltip:
              'Downloads',
          onPressed:
              () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder:
                    (_) =>
                        const DownloadQueuePage(),
              ),
            );
          },
          icon:
              Stack(
            clipBehavior:
                Clip.none,
            children: [
              Icon(
                queue.hasActiveDownloads
                    ? Icons.downloading
                    : Icons
                        .download_outlined,
              ),

              if (count >
                  0)
                Positioned(
                  right:
                      -7,
                  top:
                      -7,
                  child:
                      Container(
                    constraints:
                        const BoxConstraints(
                      minWidth:
                          18,
                      minHeight:
                          18,
                    ),
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal:
                          5,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          Theme.of(context)
                              .colorScheme
                              .primary,
                      borderRadius:
                          BorderRadius.circular(
                        10,
                      ),
                    ),
                    alignment:
                        Alignment.center,
                    child:
                        Text(
                      count >
                              99
                          ? '99+'
                          : '$count',
                      style:
                          TextStyle(
                        color:
                            Theme.of(context)
                                .colorScheme
                                .onPrimary,
                        fontSize:
                            10,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}