import 'package:flutter/material.dart';

import '../../shared/media_image.dart';

/// A fixed-size chat photo that preserves the whole image.
class ChatPhoto extends StatelessWidget {
  const ChatPhoto({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => showGeneralDialog<void>(
          context: context,
          barrierColor: Colors.black,
          transitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (_, __, ___) => ChatPhotoPreview(url: url),
        ),
        borderRadius: BorderRadius.circular(6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: VitaMediaImage(url: url, fit: BoxFit.contain),
          ),
        ),
      );
}

class ChatPhotoPreview extends StatelessWidget {
  const ChatPhotoPreview({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black,
        child: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: SizedBox.expand(
                    child: VitaMediaImage(
                      url: url,
                      fit: BoxFit.contain,
                      placeholderBuilder: (_) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            size: 48, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton(
                        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
