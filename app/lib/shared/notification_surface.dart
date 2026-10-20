import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Shared frosted surface for in-app notification banners.
class VitaNotificationSurface extends StatelessWidget {
  const VitaNotificationSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(16);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .24 : .10),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.vita.surface.withValues(alpha: dark ? .66 : .60),
              borderRadius: radius,
              border: Border.all(
                color: context.vita.green.withValues(alpha: dark ? .24 : .16),
                width: .7,
              ),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}
