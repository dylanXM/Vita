import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/media_image.dart';

/// A fixed-size chat photo that preserves the whole image.
class ChatPhoto extends StatelessWidget {
  const ChatPhoto({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => Get.to(() => ChatPhotoPreview(url: url)),
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
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.vita.pageBg,
        appBar: AppBar(
          backgroundColor: context.vita.pageBg,
          foregroundColor: context.vita.text,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Get.back(),
          ),
        ),
        body: SafeArea(
          child: SizedBox.expand(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: SizedBox.expand(
                child: VitaMediaImage(
                  url: url,
                  fit: BoxFit.contain,
                  placeholderBuilder: (_) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 48),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
