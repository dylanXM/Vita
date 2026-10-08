import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../shared/media_image.dart';
import '../billing/billing_controller.dart';
import '../chat/chat_list_controller.dart';
import '../chat/chat_list_presentation.dart';
import '../chat/chat_page.dart';
import '../companion/companion_create_method_page.dart';
import '../shell/shell_page.dart';
import '../ai_pets/ai_pets_page.dart';

/// The landing place for companions. The chat list remains in the controller,
/// but the user's first view is a character and a place instead of an inbox.
class WorldPage extends StatefulWidget {
  const WorldPage({super.key});

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _breathing;
  Timer? _sceneTimer;
  String? _sceneCompanionId;
  Map<String, dynamic>? _scene;
  int _sceneRequestId = 0;

  Future<void> _loadScene(String id) async {
    if (id.isEmpty) return;
    final requestId = ++_sceneRequestId;
    _sceneCompanionId = id;
    try {
      final data =
          await ApiClient.instance.get('/v1/companions/$id/world/scene');
      if (!mounted || _sceneCompanionId != id || _sceneRequestId != requestId)
        return;
      setState(
          () => _scene = data is Map ? Map<String, dynamic>.from(data) : null);
    } catch (_) {
      if (mounted && _sceneCompanionId == id && _sceneRequestId == requestId) {
        setState(() => _scene = null);
      }
    }
  }

  Future<void> _visit(String id) async {
    try {
      await ApiClient.instance.post('/v1/companions/$id/world/visit');
      await _loadScene(id);
    } on ApiException catch (error) {
      Get.snackbar('world.visit'.tr, error.message);
    }
  }

  void _refreshVisibleScene() {
    if (ShellController.to.index.value != 0) return;
    final companions = ChatListController.to.companions;
    if (companions.isEmpty) return;
    final selectedId = ShellController.to.selectedCompanionId.value;
    final current = companions.firstWhere(
      (item) => item['id'] == selectedId,
      orElse: () => companions.first,
    );
    final id = current['id'] as String? ?? '';
    if (id.isNotEmpty) _loadScene(id);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _breathing = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _sceneTimer = Timer.periodic(
        const Duration(minutes: 1), (_) => _refreshVisibleScene());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshVisibleScene();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _breathing.stop();
    } else if (!_breathing.isAnimating) {
      _breathing.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sceneTimer?.cancel();
    _breathing.dispose();
    super.dispose();
  }

  Future<void> _createCompanion() async {
    if (!BillingController.to.isSubscribed) {
      Get.snackbar(
          'subscription.required.title'.tr, 'subscription.required.create'.tr);
      await Get.toNamed('/subscription');
      return;
    }
    await Get.to(() => const CompanionCreateMethodPage(),
        transition: Transition.cupertino);
    await ChatListController.to.load();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ChatListController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final companions = controller.companions;
          final selectedId = ShellController.to.selectedCompanionId.value;
          final current = companions.isEmpty
              ? null
              : companions.firstWhere(
                  (item) => item['id'] == selectedId,
                  orElse: () => companions.first,
                );
          final currentId = current?['id'] as String? ?? '';
          final activeScene = _sceneCompanionId == currentId ? _scene : null;
          if (currentId != _sceneCompanionId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (currentId.isEmpty) {
                setState(() {
                  _sceneCompanionId = null;
                  _scene = null;
                });
              } else {
                setState(() => _scene = null);
                _loadScene(currentId);
              }
            });
          }
          return RefreshIndicator(
            onRefresh: () async {
              await controller.load();
              if (currentId.isNotEmpty) await _loadScene(currentId);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  20, 18, 20, VitaTabBar.reservedHeight + 34),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('world.title'.tr,
                              style: TextStyle(
                                  color: context.vita.text,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700)),
                          Text('world.subtitle'.tr,
                              style: TextStyle(
                                  color: context.vita.subText, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'world.create'.tr,
                      onPressed: _createCompanion,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  child: _WorldStage(
                    key: ValueKey(
                        '${currentId}:${activeScene?['event'] is Map ? (activeScene!['event'] as Map)['id'] : ''}:${activeScene?['campaign'] is Map ? (activeScene!['campaign'] as Map)['id'] : ''}'),
                    companion: current,
                    scene: activeScene,
                    breathing: _breathing,
                  ),
                ),
                if (current != null && activeScene != null) ...[
                  const SizedBox(height: 14),
                  _SceneSummary(scene: activeScene),
                ],
                if (companions.length > 1) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: companions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final item = companions[index];
                        final selected = item['id'] == current?['id'];
                        final unread =
                            ChatListPresentation.from(item).unreadCount;
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${item['name'] ?? 'chat.companion'.tr}'),
                              if (unread > 0) ...[
                                const SizedBox(width: 6),
                                Text(unread > 99 ? '99+' : '$unread',
                                    style: TextStyle(
                                        color: context.vita.red,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ],
                          ),
                          selected: selected,
                          onSelected: (_) => ShellController
                              .to
                              .selectedCompanionId
                              .value = item['id'] as String?,
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (current == null)
                  FilledButton.icon(
                    onPressed: _createCompanion,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text('world.create'.tr),
                  )
                else ...[
                  if (activeScene != null) ...[
                    _WorldAction(
                      icon: (activeScene['visited_today'] == true)
                          ? Icons.check_circle_outline
                          : Icons.favorite_border,
                      title: (activeScene['visited_today'] == true)
                          ? 'world.visited'.tr
                          : 'world.visit'.tr,
                      onTap: (activeScene['visited_today'] == true)
                          ? null
                          : () => _visit(currentId),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _WorldAction(
                    icon: Icons.chat_bubble_outline,
                    title: 'world.talk'.tr,
                    subtitle: 'world.talkHint'.tr,
                    onTap: () async {
                      final id = current['id'] as String? ?? '';
                      if (id.isEmpty) return;
                      await Get.to(() => ChatPage(
                            companionId: id,
                            name: '${current['name'] ?? 'chat.companion'.tr}',
                            companion: current,
                          ));
                      await controller.load();
                      await _loadScene(id);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _WorldAction(
                          icon: Icons.auto_stories_outlined,
                          title: 'world.journey'.tr,
                          onTap: () => ShellController.to.switchTo(1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WorldAction(
                          icon: Icons.explore_outlined,
                          title: 'world.discover'.tr,
                          onTap: () => ShellController.to.switchTo(2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _WorldAction(
                    icon: Icons.pets_outlined,
                    title: 'world.petGarden'.tr,
                    onTap: () => Get.to(() => const AIPetsPage()),
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _SceneSummary extends StatelessWidget {
  const _SceneSummary({required this.scene});

  final Map<String, dynamic> scene;

  @override
  Widget build(BuildContext context) {
    final event = scene['event'] is Map
        ? Map<String, dynamic>.from(scene['event'] as Map)
        : <String, dynamic>{};
    final place = scene['place'] is Map
        ? Map<String, dynamic>.from(scene['place'] as Map)
        : <String, dynamic>{};
    final campaign = scene['campaign'] is Map
        ? Map<String, dynamic>.from(scene['campaign'] as Map)
        : <String, dynamic>{};
    final memories = scene['memories'] is List
        ? (scene['memories'] as List).whereType<Map>().toList()
        : <Map>[];
    final connections = scene['connections'] is List
        ? (scene['connections'] as List).whereType<Map>().toList()
        : <Map>[];
    final location = (event['location'] as String? ?? '').trim();
    final description = (event['description'] as String? ?? '').trim();
    final placeDescription = (place['description'] as String? ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: context.vita.surface, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.brightness_5_outlined,
                size: 17, color: context.vita.green),
            const SizedBox(width: 7),
            Expanded(
                child: Text('world.phase.${scene['phase'] ?? 'quiet'}'.tr,
                    style: TextStyle(
                        color: context.vita.text,
                        fontWeight: FontWeight.w600))),
            Text('world.mood'.trParams({'n': '${scene['mood'] ?? 50}'}),
                style: TextStyle(color: context.vita.subText, fontSize: 12)),
          ]),
          const SizedBox(height: 12),
          if (campaign.isNotEmpty) ...[
            Row(children: [
              Icon(Icons.celebration_outlined,
                  size: 18, color: context.vita.green),
              const SizedBox(width: 7),
              Expanded(
                  child: Text('${campaign['title'] ?? ''}',
                      style: TextStyle(
                          color: context.vita.green,
                          fontWeight: FontWeight.w700)))
            ]),
            if ('${campaign['description'] ?? ''}'.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text('${campaign['description']}',
                      style: TextStyle(
                          color: context.vita.subText, fontSize: 12))),
            const SizedBox(height: 12),
          ],
          if (location.isNotEmpty)
            Text(location,
                style: TextStyle(
                    color: context.vita.text, fontWeight: FontWeight.w700)),
          if (description.isNotEmpty || placeDescription.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                    description.isNotEmpty ? description : placeDescription.tr,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: context.vita.subText, fontSize: 13))),
          if (memories.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('world.memories'.tr,
                style: TextStyle(
                    color: context.vita.text, fontWeight: FontWeight.w700)),
            Text(
                memories.first['kind'] == 'world_visit'
                    ? 'world.visitMemory'.tr
                    : '${memories.first['content'] ?? ''}'.tr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.vita.subText, fontSize: 12)),
          ],
          if (connections.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('world.connections'.tr,
                style: TextStyle(
                    color: context.vita.text, fontWeight: FontWeight.w700)),
            Text(
                connections
                    .map((item) => '${item['name'] ?? ''}')
                    .where((name) => name.isNotEmpty)
                    .join(' · '),
                style: TextStyle(color: context.vita.subText, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _WorldStage extends StatelessWidget {
  const _WorldStage(
      {super.key,
      required this.companion,
      required this.scene,
      required this.breathing});

  final Map<String, dynamic>? companion;
  final Map<String, dynamic>? scene;
  final Animation<double> breathing;

  @override
  Widget build(BuildContext context) {
    final hour = scene?['local_hour'] is int
        ? scene!['local_hour'] as int
        : DateTime.now().hour;
    final night = hour < 6 || hour >= 18;
    final name = '${companion?['name'] ?? 'world.emptyTitle'.tr}';
    final portrait = companion?['portrait_url'] as String? ?? '';
    final place = scene?['place'] is Map
        ? Map<String, dynamic>.from(scene!['place'] as Map)
        : <String, dynamic>{};
    final event = scene?['event'] is Map
        ? Map<String, dynamic>.from(scene!['event'] as Map)
        : <String, dynamic>{};
    final campaign = scene?['campaign'] is Map
        ? Map<String, dynamic>.from(scene!['campaign'] as Map)
        : <String, dynamic>{};
    final kind = place['kind'] as String? ?? 'home';
    final visualKind = campaign['scene_kind'] as String? ?? kind;
    final ambience = campaign['ambience'] as String? ?? 'clear';
    final colors = switch (visualKind) {
      'work' => const [Color(0xFF526788), Color(0xFF9E99BB), Color(0xFFC7B9C5)],
      'cafe' => const [Color(0xFF9A615B), Color(0xFFC99883), Color(0xFFF1C9A5)],
      'outdoors' => const [
          Color(0xFF3F7A83),
          Color(0xFF8BB4A7),
          Color(0xFFC9D9B4)
        ],
      'story' => const [
          Color(0xFF564373),
          Color(0xFF9E7EA7),
          Color(0xFFD5AFC1)
        ],
      _ => night
          ? const [Color(0xFF242048), Color(0xFF594776), Color(0xFF967796)]
          : const [Color(0xFFB6B5F5), Color(0xFFE4C3D5), Color(0xFFFFD7B3)],
    };
    final latest = companion == null
        ? null
        : ChatListPresentation.from(companion!).preview(
            fallback: 'world.ready'.tr,
            voiceLabel: 'chat.voiceMessage'.tr,
            photoLabel: 'chat.photoMessage'.tr,
          );
    return Container(
      height: 420,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
                painter: _WorldBackdropPainter(visualKind, ambience)),
          ),
          const Positioned(
            top: 54,
            right: 38,
            child: Icon(Icons.auto_awesome, size: 38, color: Color(0x88FFFFFF)),
          ),
          Positioned(
            left: 22,
            top: 22,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: const Color(0x66302C47),
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                child: Text('${place['title'] ?? 'world.place.home'.tr}'.tr,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          Positioned(
            right: -62,
            bottom: -170,
            child: Container(
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
          Positioned(
            left: -70,
            bottom: -170,
            child: Container(
              width: 310,
              height: 310,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF8D78B7).withValues(alpha: 0.22),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.1),
            child: AnimatedBuilder(
              animation: breathing,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                    0,
                    MediaQuery.disableAnimationsOf(context)
                        ? 0
                        : (breathing.value - 0.5) * 10),
                child: child,
              ),
              child: portrait.isEmpty
                  ? Icon(Icons.auto_awesome,
                      size: 132, color: Colors.white.withValues(alpha: 0.82))
                  : Container(
                      width: 230,
                      height: 280,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(110),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 30,
                              offset: Offset(0, 18)),
                        ],
                      ),
                      child: VitaMediaImage(url: portrait, fit: BoxFit.cover),
                    ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xAA201C37),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    companion == null
                        ? 'world.emptyHint'.tr
                        : companion?['friendship_active'] == false
                            ? 'chat.notFriends'.tr
                            : event['title'] is String &&
                                    (event['title'] as String).isNotEmpty
                                ? event['title'] as String
                                : latest ?? 'world.ready'.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Color(0xFFE7DEF3), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldBackdropPainter extends CustomPainter {
  const _WorldBackdropPainter(this.kind, this.ambience);

  final String kind;
  final String ambience;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.21)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final fill = Paint()..color = Colors.white.withValues(alpha: 0.13);
    final floor = size.height * 0.77;
    canvas.drawLine(Offset(0, floor), Offset(size.width, floor), line);
    if (kind == 'outdoors') {
      final hills = Path()
        ..moveTo(0, floor)
        ..quadraticBezierTo(
            size.width * .24, floor - 85, size.width * .52, floor - 15)
        ..quadraticBezierTo(
            size.width * .8, floor - 110, size.width, floor - 30)
        ..lineTo(size.width, floor)
        ..close();
      canvas.drawPath(hills, fill);
      canvas.drawCircle(Offset(size.width * .8, 78), 32, line);
      _paintWeather(canvas, size);
      return;
    }
    final window = RRect.fromRectAndRadius(
        Rect.fromLTWH(28, 60, 88, 138), const Radius.circular(44));
    canvas.drawRRect(window, line);
    canvas.drawLine(const Offset(72, 60), const Offset(72, 198), line);
    if (kind == 'cafe') {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(size.width * .72, floor - 22),
              width: 132,
              height: 28),
          fill);
      canvas.drawRect(Rect.fromLTWH(size.width * .7, floor - 62, 38, 38), line);
    } else if (kind == 'work') {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(size.width * .51, floor - 70, size.width * .43, 60),
              const Radius.circular(6)),
          line);
      for (var i = 0; i < 4; i++) {
        canvas.drawRect(Rect.fromLTWH(34 + i * 16.0, floor - 54, 11, 50), fill);
      }
    } else if (kind == 'story') {
      for (var i = 0; i < 3; i++) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(size.width * .6 + i * 29, 88, 22, floor - 102),
                const Radius.circular(3)),
            line);
      }
    } else {
      canvas.drawCircle(Offset(size.width * .82, floor - 64), 34, fill);
      canvas.drawLine(Offset(size.width * .82, floor - 30),
          Offset(size.width * .82, floor), line);
    }
    _paintWeather(canvas, size);
  }

  void _paintWeather(Canvas canvas, Size size) {
    if (ambience == 'clear') return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.36)
      ..strokeWidth = 2;
    for (var i = 0; i < 20; i++) {
      final x = ((i * 83) % 97) / 97 * size.width;
      final y = ((i * 47) % 89) / 89 * size.height * .7;
      if (ambience == 'snow') {
        canvas.drawCircle(Offset(x, y), 2.5, paint);
      } else if (ambience == 'rain') {
        canvas.drawLine(Offset(x, y), Offset(x - 5, y + 15), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WorldBackdropPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.ambience != ambience;
}

class _WorldAction extends StatelessWidget {
  const _WorldAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Icon(icon, color: context.vita.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: context.vita.text,
                              fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(
                                color: context.vita.subText, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
