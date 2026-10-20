import 'package:flutter/material.dart';

/// Stable gift artwork on devices whose emoji fonts do not contain a glyph.
IconData giftVisualIcon(String productKey) => switch (productKey) {
      'gift_coffee' => Icons.local_cafe_rounded,
      'gift_flowers' => Icons.local_florist_rounded,
      'gift_cake' => Icons.cake_rounded,
      'gift_keepsake' => Icons.redeem_rounded,
      _ => Icons.card_giftcard_rounded,
    };
