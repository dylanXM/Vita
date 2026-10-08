import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme.dart';

/// 右下角悬浮操作按钮：点击展开操作面板。
/// 面板包含状态条（饱腹/开心/精力/健康）、经验/金币，以及
/// 喂食 / 喝水 / 散步 / 坐下 / 睡觉 / 刷新操作。
class PetActionMenu extends StatefulWidget {
  const PetActionMenu({
    super.key,
    required this.level,
    required this.coins,
    required this.experience,
    required this.state,
    required this.feeding,
    required this.feedCost,
    required this.onFeed,
    required this.onDrink,
    required this.onWalk,
    required this.onSit,
    required this.onRest,
    required this.onRefresh,
  });

  final int level;
  final int coins;
  final int experience;
  final Map<String, dynamic> state;
  final bool feeding;
  final int feedCost;
  final VoidCallback onFeed;
  final VoidCallback onDrink;
  final VoidCallback onWalk;
  final VoidCallback onSit;
  final VoidCallback onRest;
  final VoidCallback onRefresh;

  @override
  State<PetActionMenu> createState() => _PetActionMenuState();
}

class _PetActionMenuState extends State<PetActionMenu>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _pulseController;
  late final Animation<double> _panelScale;
  late final Animation<double> _panelFade;
  late final Animation<Offset> _panelSlide;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    // 收起时主按钮轻微呼吸脉动。
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    final curved =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _panelScale = Tween<double>(begin: .8, end: 1).animate(curved);
    _panelFade = Tween<double>(begin: 0, end: 1).animate(curved);
    _panelSlide = Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero)
        .animate(curved);
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      _controller.reverse();
      _pulseController.repeat();
    } else {
      _controller.forward();
      _pulseController.stop();
    }
    setState(() => _expanded = !_expanded);
  }

  void _run(VoidCallback action) {
    _toggle();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 展开的面板。
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_controller.value == 0 && !_expanded) {
              return const SizedBox.shrink();
            }
            return Opacity(
              opacity: _panelFade.value,
              child: Transform.scale(
                scale: _panelScale.value,
                child: Transform.translate(
                  offset: _panelSlide.value * 40,
                  child: _buildPanel(context),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        // 悬浮主按钮。
        _buildFab(context),
      ],
    );
  }

  Widget _buildPanel(BuildContext context) {
    final vita = context.vita;
    final state = widget.state;
    final level = widget.level;
    return Container(
      width: 268,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: vita.surface.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: vita.glassRing, width: .8),
        boxShadow: [
          BoxShadow(
              color: vita.glassShadow,
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('aiPets.title'.tr,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: vita.text)),
            ),
            Text('aiPets.level'.trParams({'level': '$level'}),
                style: TextStyle(fontSize: 12, color: vita.subText)),
            const SizedBox(width: 10),
            _IconButton(
              icon: Icons.refresh,
              tooltip: 'aiPets.refresh',
              onTap: () => _run(widget.onRefresh),
            ),
            const SizedBox(width: 2),
            _IconButton(
              icon: Icons.close,
              tooltip: 'common.cancel',
              onTap: _toggle,
            ),
          ]),
          const SizedBox(height: 10),
          _StatusBar(
              label: 'aiPets.hunger'.tr,
              value: (state['hunger'] as num?)?.toInt() ?? 0,
              color: Colors.orange),
          _StatusBar(
              label: 'aiPets.happiness'.tr,
              value: (state['happiness'] as num?)?.toInt() ?? 0,
              color: Colors.pink),
          _StatusBar(
              label: 'aiPets.energy'.tr,
              value: (state['energy'] as num?)?.toInt() ?? 0,
              color: Colors.blue),
          _StatusBar(
              label: 'aiPets.health'.tr,
              value: (state['health'] as num?)?.toInt() ?? 0,
              color: vita.green),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
                'aiPets.experience'.trParams({'value': '${widget.experience}'}),
                style: TextStyle(fontSize: 11.5, color: vita.subText)),
            Text('aiPets.coins'.trParams({'value': '${widget.coins}'}),
                style: TextStyle(fontSize: 11.5, color: vita.subText)),
          ]),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _ActionTile(
            icon: Icons.restaurant,
            iconColor: Colors.orange,
            label: widget.feeding
                ? 'aiPets.feeding'.tr
                : 'aiPets.feed'.trParams({'coins': '${widget.feedCost}'}),
            onTap: widget.feeding ? null : () => _run(widget.onFeed),
          ),
          _ActionTile(
            icon: Icons.water_drop_outlined,
            iconColor: const Color(0xFF67B9DB),
            label: 'aiPets.drink'.tr,
            onTap: widget.feeding ? null : () => _run(widget.onDrink),
          ),
          Row(children: [
            _QuickAction(
                icon: Icons.directions_walk_rounded,
                label: 'aiPets.walk'.tr,
                onTap: widget.feeding ? null : () => _run(widget.onWalk)),
            _QuickAction(
                icon: Icons.chair_alt_rounded,
                label: 'aiPets.sit'.tr,
                onTap: widget.feeding ? null : () => _run(widget.onSit)),
            _QuickAction(
                icon: Icons.bedtime_outlined,
                label: 'aiPets.rest'.tr,
                onTap: widget.feeding ? null : () => _run(widget.onRest)),
          ]),
        ],
      ),
    );
  }

  Widget _buildFab(BuildContext context) {
    final vita = context.vita;
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _pulseController]),
      builder: (context, _) {
        // 未展开时轻微呼吸脉动，展开时旋转到关闭图标。
        final pulse = _expanded
            ? 1.0
            : 1 + .03 * math.sin(_pulseController.value * math.pi * 2);
        final angle = _controller.value * .5;
        return Transform.rotate(
          angle: angle,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            elevation: 0,
            child: InkWell(
              onTap: _toggle,
              customBorder: const CircleBorder(),
              child: Container(
                width: 60 * pulse,
                height: 60 * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: vita.brandGradient.colors,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: vita.greenDark.withValues(alpha: .4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  _expanded ? Icons.close : Icons.pets_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 21, color: onTap == null ? vita.hint : vita.text),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: onTap == null ? vita.hint : vita.text)),
          ]),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Tooltip(
      message: tooltip.tr,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: vita.subText),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: onTap == null ? vita.hint : vita.text)),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 16, color: vita.chevron),
        ]),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        SizedBox(
            width: 52,
            child: Text(label,
                style: TextStyle(fontSize: 11.5, color: vita.subText))),
        Expanded(
            child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                    value: value.clamp(0, 100) / 100,
                    minHeight: 6,
                    backgroundColor: vita.pageBg,
                    valueColor: AlwaysStoppedAnimation(color)))),
        const SizedBox(width: 8),
        SizedBox(
            width: 26,
            child: Text('$value',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: vita.subText))),
      ]),
    );
  }
}
