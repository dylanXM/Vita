import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme.dart';
import 'media_image.dart';

/// Small shared widgets used across features.

class VitaAvatar extends StatelessWidget {
  const VitaAvatar({
    super.key,
    required this.name,
    this.radius = 24,
    this.background,
    this.textColor,
    this.imageUrl,
    this.borderRadius,
  });

  final String name;
  final double radius;

  /// Optional background override (e.g. white on gradient headers).
  final Color? background;
  final Color? textColor;
  final String? imageUrl;

  /// When non-null, render a rounded-square avatar instead of a circle.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final source = imageUrl?.trim() ?? '';
    final hasImage = source.isNotEmpty;
    Widget content() => hasImage
        ? source.startsWith('asset://')
            ? Image.asset(source.substring('asset://'.length),
                fit: BoxFit.cover)
            : VitaMediaImage(url: source)
        : Center(
            child: Text(
              initial,
              style: TextStyle(
                color: textColor ?? context.vita.green,
                fontSize: radius * 0.9,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
    if (borderRadius != null) {
      final size = radius * 2;
      return ClipRRect(
        borderRadius: borderRadius!,
        child: Container(
          width: size,
          height: size,
          color: background ?? context.vita.green.withValues(alpha: 0.18),
          child: content(),
        ),
      );
    }
    return ClipOval(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        color: background ?? context.vita.green.withValues(alpha: 0.18),
        child: content(),
      ),
    );
  }
}

/// Flat white section used by WeChat-style grouped pages.
class VitaCard extends StatelessWidget {
  const VitaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.radius = 0,
    this.shadow = const [],
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

/// Compact, centered top-level header. Subtitles are intentionally omitted so
/// the hierarchy matches the rest of the app's navigation bars.
class VitaTabHeader extends StatelessWidget {
  const VitaTabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showDivider = true,
  });

  final String title;
  final String? subtitle;
  final Widget? actions;

  /// Hairline under the header. The four root tab pages turn it off so the
  /// title reads as part of the content; pushed pages keep it as a nav bar rule.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Full width is required: inside a Column's loose constraints the
      // Container/Stack would shrink to the title's width, which would make
      // the trailing `Positioned(right: 8)` action hug the centered title
      // instead of the screen's right edge.
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: context.vita.pageBg,
        border: showDivider
            ? Border(
                bottom: BorderSide(color: context.vita.divider, width: 0.5))
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.vita.text),
          ),
          if (actions != null)
            Positioned(
                right: 8, top: 0, bottom: 0, child: Center(child: actions!)),
        ],
      ),
    );
  }
}

/// Compact segmented selector for picking a companion.
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
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? context.vita.green : context.vita.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: selected ? context.vita.green : context.vita.divider,
                ),
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

/// Loading row matching the flat conversation list.
class VitaSkeletonCard extends StatelessWidget {
  const VitaSkeletonCard({super.key, this.withAvatar = true});

  final bool withAvatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.vita.surface,
        border:
            Border(bottom: BorderSide(color: context.vita.divider, width: 0.5)),
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
            Icon(
              icon,
              size: 56,
              color: context.vita.hint,
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
    this.icon,
    this.customIcon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.borderRadius,
    this.showChevron = true,
  }) : assert(icon != null || customIcon != null,
            'Either icon or customIcon must be provided');

  final IconData? icon;

  /// Optional fully custom leading widget (e.g. a colored SVG). When set, it
  /// replaces the default [Icon] rendered inside the 30x30 tile badge.
  final Widget? customIcon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? iconColor;
  final BorderRadius? borderRadius;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = iconColor ?? context.vita.green;
    return Material(
      color: context.vita.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: customIcon == null
                      ? accent.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: customIcon ?? Icon(icon, color: accent, size: 18),
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
              if (showChevron)
                Icon(Icons.chevron_right,
                    size: 20, color: context.vita.chevron),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flat, single-stroke menu icon used by the Explore, Me and Settings lists.
///
/// The fixed canvas keeps icons from different Material families visually
/// aligned while the semantic color makes each destination easy to scan.
class VitaMenuIcon extends StatelessWidget {
  const VitaMenuIcon({
    super.key,
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 30,
        child: Center(child: Icon(icon, size: 24, color: color)),
      );
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
            borderRadius: BorderRadius.circular(4),
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

/// Formats a timestamp without an English-only month abbreviation.
String formatDate(DateTime t) {
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// "Today" / "Yesterday" / short date — for chat date separators.
String formatDateSeparator(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'common.today'.tr;
  if (diff == 1) return 'common.yesterday'.tr;
  return formatDate(t);
}

/// True when both timestamps fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
