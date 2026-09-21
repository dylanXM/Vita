import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Pet artwork shared by the full home scene and the app-wide floating pet.
/// Default pets have a dedicated closed-eye frame; custom Admin artwork falls
/// back to its normal image so it can still participate in motion animations.
class AIPetAvatar extends StatelessWidget {
  const AIPetAvatar({
    super.key,
    required this.name,
    required this.imageUrl,
    this.blinkAmount = 0,
  });

  final String name;
  final String imageUrl;
  final double blinkAmount;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => ColoredBox(
          color: const Color(0xFFFFE9D7),
          child: Center(
            child:
                Icon(Icons.pets_rounded, size: 52, color: context.vita.green),
          ),
        );

    if (imageUrl.startsWith('asset://')) {
      final assetPath = imageUrl.substring('asset://'.length);
      final closedEyeAsset = aiPetClosedEyeAssetPath(imageUrl);
      final openEyes = Image.asset(
        assetPath,
        fit: BoxFit.contain,
        semanticLabel: name,
        errorBuilder: (_, __, ___) => fallback(),
      );
      if (closedEyeAsset == null) return openEyes;
      return Stack(fit: StackFit.expand, children: [
        openEyes,
        Opacity(
          opacity: blinkAmount.clamp(0.0, 1.0),
          child: Image.asset(closedEyeAsset, fit: BoxFit.contain),
        ),
      ]);
    }
    if (imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.contain,
        semanticLabel: name,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }
    return fallback();
  }
}

String? aiPetClosedEyeAssetPath(String imageUrl) {
  if (!imageUrl.startsWith('asset://assets/ai_pets/') ||
      imageUrl.endsWith('_blink.png')) {
    return null;
  }
  final assetPath = imageUrl.substring('asset://'.length);
  const supportedAssets = {
    'assets/ai_pets/cat_orange.png',
    'assets/ai_pets/cat_ragdoll.png',
    'assets/ai_pets/cat_tuxedo.png',
    'assets/ai_pets/dog_corgi.png',
    'assets/ai_pets/dog_retriever.png',
    'assets/ai_pets/dog_shiba.png',
  };
  if (!supportedAssets.contains(assetPath)) return null;
  return assetPath.replaceFirst('.png', '_blink.png');
}
