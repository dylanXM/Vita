import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Small shared widgets used across features.

class VitaAvatar extends StatelessWidget {
  const VitaAvatar({super.key, required this.name, this.radius = 24});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: VitaColors.green.withValues(alpha: 0.18),
      child: Text(
        initial,
        style: TextStyle(
          color: VitaColors.green,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class VitaEmpty extends StatelessWidget {
  const VitaEmpty({super.key, required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: VitaColors.subText.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: VitaColors.subText, fontSize: 15)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: VitaColors.subText.withValues(alpha: 0.7), fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// White card row with a chevron, in the settings-list style.
class VitaListTile extends StatelessWidget {
  const VitaListTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: VitaColors.green, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, color: VitaColors.text)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: const TextStyle(fontSize: 13, color: VitaColors.subText)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              const Icon(Icons.chevron_right, size: 20, color: VitaColors.subText),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formats a timestamp as HH:mm.
String formatClock(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Formats a timestamp as a short date (Sep 19).
String formatDate(DateTime t) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[t.month - 1]} ${t.day}';
}
