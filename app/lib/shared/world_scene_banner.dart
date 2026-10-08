import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'media_image.dart';

/// Scenic introduction shared by the world's destinations.
class WorldSceneBanner extends StatelessWidget {
  const WorldSceneBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.imageUrl,
    this.height = 188,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? imageUrl;
  final double height;

  @override
  Widget build(BuildContext context) {
    final portrait = imageUrl?.trim() ?? '';
    return Container(
      height: height,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: context.vita.brandGradient,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -42,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            right: portrait.isEmpty ? 22 : 0,
            top: portrait.isEmpty ? 32 : 0,
            bottom: portrait.isEmpty ? null : 0,
            child: portrait.isEmpty
                ? Icon(icon,
                    size: 106, color: Colors.white.withValues(alpha: 0.28))
                : SizedBox(
                    width: 155,
                    child: VitaMediaImage(url: portrait, fit: BoxFit.cover),
                  ),
          ),
          Positioned(
            left: 20,
            right: portrait.isEmpty ? 20 : 120,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFEDE7FF), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
