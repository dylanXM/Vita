import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Small shared widgets used across features.

class VitaAvatar extends StatelessWidget {
  const VitaAvatar({
    super.key,
    required this.name,
    this.radius = 24,
    this.background,
    this.textColor,
    this.imageUrl,
  });

  final String name;
  final double radius;

  /// Optional background override (e.g. white on gradient headers).
  final Color? background;
  final Color? textColor;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final source = imageUrl?.trim() ?? '';
    final ImageProvider<Object>? image = source.startsWith('asset://')
        ? AssetImage(source.substring('asset://'.length))
        : source.isNotEmpty
            ? NetworkImage(source)
            : null;
    return CircleAvatar(
      radius: radius,
      backgroundColor: background ?? context.vita.green.withValues(alpha: 0.18),
      backgroundImage: image,
      child: image == null
          ? Text(
              initial,
              style: TextStyle(
                color: textColor ?? context.vita.green,
                fontSize: radius * 0.9,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}

/// White rounded card with the standard Vita shadow.
class VitaCard extends StatelessWidget {
  const VitaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.radius = VitaRadius.md,
    this.shadow = VitaShadow.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final List<BoxShadow> shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Modern tab header: large title, optional subtitle and trailing actions.
class VitaTabHeader extends StatelessWidget {
  const VitaTabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.vita.pageTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 13, color: context.vita.subText),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) actions!,
        ],
      ),
    );
  }
}

/// Horizontal pill chips for picking a companion (replaces dropdowns).
class VitaCompanionChips extends StatelessWidget {
  const VitaCompanionChips({
    super.key,
    required this.companions,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> companions;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: companions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = companions[i];
          final name = c['name'] as String? ?? 'Companion';
          final selected = selectedId == c['id'];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(c['id'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? context.vita.green : context.vita.surface,
                borderRadius: BorderRadius.circular(VitaRadius.pill),
                border: Border.all(
                  color: selected ? context.vita.green : context.vita.divider,
                ),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x2207C160),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : const [],
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : context.vita.text,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shimmer placeholder for loading states.
class VitaSkeleton extends StatefulWidget {
  const VitaSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 7,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<VitaSkeleton> createState() => _VitaSkeletonState();
}

class _VitaSkeletonState extends State<VitaSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                t - 0.3,
                t,
                t + 0.3,
              ].map((s) => s.clamp(0.0, 1.0)).toList(),
              colors: [
                context.vita.shimmerA,
                context.vita.shimmerB,
                context.vita.shimmerA,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Card-shaped skeleton row matching the modern list cards.
class VitaSkeletonCard extends StatelessWidget {
  const VitaSkeletonCard({super.key, this.withAvatar = true});

  final bool withAvatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(VitaRadius.md),
        boxShadow: VitaShadow.card,
      ),
      child: Row(
        children: [
          if (withAvatar) ...[
            const SizedBox(
              width: 52,
              height: 52,
              child: VitaSkeleton(width: 52, height: 52, radius: 26),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                VitaSkeleton(height: 16, radius: 8),
                SizedBox(height: 10),
                VitaSkeleton(width: 140, height: 12, radius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VitaEmpty extends StatelessWidget {
  const VitaEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

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
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: context.vita.green.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 44,
                color: context.vita.green.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                color: context.vita.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.vita.subText,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Card row with a tinted icon and a chevron, in the settings-list style.
class VitaListTile extends StatelessWidget {
  const VitaListTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.borderRadius,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? iconColor;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = iconColor ?? context.vita.green;
    return Material(
      color: context.vita.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.circular(VitaRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: context.vita.text,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: context.vita.subText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              Icon(Icons.chevron_right, size: 20, color: context.vita.chevron),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centered pill chip used for chat date separators.
class VitaDateChip extends StatelessWidget {
  const VitaDateChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: context.vita.surface,
            borderRadius: BorderRadius.circular(VitaRadius.pill),
            border: Border.all(color: context.vita.divider),
          ),
          child: Text(label, style: context.vita.caption),
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
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[t.month - 1]} ${t.day}';
}

/// "Today" / "Yesterday" / short date — for chat date separators.
String formatDateSeparator(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return formatDate(t);
}

/// True when both timestamps fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
