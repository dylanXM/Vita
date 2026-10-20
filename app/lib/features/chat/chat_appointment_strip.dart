import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'chat_list_controller.dart';
import 'companion_moment_page.dart';

class ChatAppointmentStrip extends StatefulWidget {
  const ChatAppointmentStrip({super.key});

  @override
  State<ChatAppointmentStrip> createState() => _ChatAppointmentStripState();
}

class _ChatAppointmentStripState extends State<ChatAppointmentStrip>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse;
  bool _opening = false;
  bool _foreground = true;
  bool _reduced = false;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _pulse = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 1600));
  }

  void _sync() {
    if (_foreground && !_reduced && _visible) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _visible = TickerMode.of(context);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _open(Map<String, dynamic> date, Map<String, dynamic> companion) async {
    if (_opening) return;
    _opening = true;
    final name = '${companion['name'] ?? ''}';
    final label = (date['started'] == true
        ? 'world.appointment.continue' : 'world.appointment.enter').tr;
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (dialog) {
        final vita = dialog.vita;
        final starts = DateTime.tryParse('${date['starts_at'] ?? ''}')?.toLocal();
        return AlertDialog(
          scrollable: true,
          backgroundColor: vita.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(label, style: TextStyle(color: vita.text)),
          content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('chat.dateConfirm'.trParams({'name': name}),
                style: TextStyle(color: vita.text)),
              const SizedBox(height: 12),
              Text('${date['title_key'] ?? ''}'.tr, style: TextStyle(color: vita.green)),
              if (starts != null) Text(
                '${MaterialLocalizations.of(dialog).formatMediumDate(starts)} · '
                '${TimeOfDay.fromDateTime(starts).format(dialog)}',
                style: TextStyle(color: vita.subText)),
            ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(false),
              child: Text('common.cancel'.tr)),
            FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: Text(label)),
          ],
        );
      });
      if (confirmed != true || !mounted) return;
      await Get.to(() => CompanionMomentPage(
        companionId: '${companion['id']}', eventId: '${date['id']}', name: name,
        avatarUrl: companion['portrait_url'] as String?), transition: Transition.cupertino);
      if (mounted) await ChatListController.to.load(silent: true);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final ctrl = ChatListController.to;
    final companions = {for (final c in ctrl.filtered) '${c['id']}': c};
    final dates = ctrl.appointments.where((date) {
      final end = DateTime.tryParse('${date['ends_at'] ?? ''}');
      return companions.containsKey('${date['companion_id']}') &&
          '${date['id'] ?? ''}'.isNotEmpty && end != null && end.isAfter(DateTime.now());
    }).toList();
    if (dates.isEmpty) return const SizedBox.shrink();
    final vita = context.vita;
    return SizedBox(height: 100, child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      itemCount: dates.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final date = dates[index];
        final companion = companions['${date['companion_id']}']!;
        final name = '${companion['name'] ?? ''}';
        return Semantics(button: true,
          label: '$name · ${'world.appointment.enter'.tr}',
          child: InkWell(borderRadius: BorderRadius.circular(18),
            onTap: () => _open(date, companion),
            child: SizedBox(width: 72, child: Column(children: [
              SizedBox(width: 60, height: 60, child: Stack(children: [
                Center(child: Container(padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: vita.green.withValues(alpha: .55))),
                  child: VitaAvatar(name: name, radius: 23,
                    imageUrl: companion['portrait_url'] as String?,
                    borderRadius: BorderRadius.circular(23)))),
                Positioned(top: 0, right: 0, child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, _reduced ? 0 : -3 * math.sin(_pulse.value * math.pi).abs()),
                    child: child),
                  child: Container(width: 24, height: 24,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: vita.surface,
                      border: Border.all(color: vita.green.withValues(alpha: .35))),
                    child: Icon(Icons.favorite_rounded, color: vita.green, size: 14)),
                )),
              ])),
              const SizedBox(height: 4),
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: vita.text, fontSize: 12))),
            ])),
          ),
        );
      },
    ));
  });
}
