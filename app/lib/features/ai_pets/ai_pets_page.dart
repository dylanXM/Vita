import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../chat/chat_list_controller.dart';
import '../chat/chat_page.dart';
import '../life/life_detail_page.dart';
import '../memories/memories_page.dart';
import 'ai_pet_avatar.dart';
import 'ai_pet_desktop_controller.dart';

class AIPetsPage extends StatefulWidget {
  const AIPetsPage({super.key});

  @override
  State<AIPetsPage> createState() => _AIPetsPageState();
}

class _AIPetsPageState extends State<AIPetsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _breeds = const [];

  @override
  void initState() {
    super.initState();
    AnalyticsService.to.track('ai_pets_viewed', category: 'companion');
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/v1/ai-pets/breeds');
      final items = data is Map ? data['items'] : null;
      if (mounted && items is List) {
        setState(() => _breeds = items
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList());
      }
    } catch (_) {
      // Keep Explore usable when remote pet content is temporarily unavailable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openBreed(Map<String, dynamic> breed) async {
    final adoptedId = '${breed['adopted_companion_id'] ?? ''}';
    if (adoptedId.isNotEmpty) {
      await Get.to(() => AIPetHomePage(
            companionId: adoptedId,
            name: '${breed['adopted_companion_name'] ?? breed['name'] ?? ''}',
            avatarUrl: '${breed['avatar_url'] ?? ''}',
            species: '${breed['species'] ?? ''}',
          ));
      await _load();
      return;
    }
    if (breed['can_adopt'] != true) {
      Get.snackbar(
          'subscription.required.title'.tr, 'aiPets.subscriptionRequired'.tr);
      Get.toNamed('/subscription');
      return;
    }
    final nameController =
        TextEditingController(text: '${breed['name'] ?? ''}');
    final confirmed = await Get.dialog<bool>(AlertDialog(
      title: Text('aiPets.adoptTitle'.tr),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${breed['description'] ?? ''}'),
            const SizedBox(height: 16),
            TextField(
                controller: nameController,
                autofocus: true,
                maxLength: 40,
                decoration: InputDecoration(labelText: 'aiPets.petName'.tr)),
          ]),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('common.cancel'.tr)),
        FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('aiPets.adopt'.tr)),
      ],
    ));
    if (confirmed != true || nameController.text.trim().isEmpty) {
      nameController.dispose();
      return;
    }
    try {
      final result = await ApiClient.instance.post('/v1/ai-pets/adopt', data: {
        'breed_id': breed['id'],
        'name': nameController.text.trim(),
      });
      final companionId =
          result is Map ? '${result['companion_id'] ?? ''}' : '';
      AnalyticsService.to.track('ai_pet_adopted',
          category: 'companion',
          properties: {
            'breed_id': '${breed['id'] ?? ''}',
            'companion_id': companionId
          });
      await Future.wait([
        ChatListController.to.load(),
        MemoriesController.to.loadCompanions(),
        if (Get.isRegistered<AIPetDesktopController>())
          AIPetDesktopController.to.refreshPet(),
      ]);
      if (mounted && companionId.isNotEmpty) {
        await Get.to(() => AIPetHomePage(
              companionId: companionId,
              name: nameController.text.trim(),
              avatarUrl: '${breed['avatar_url'] ?? ''}',
              species: '${breed['species'] ?? ''}',
            ));
      }
      await _load();
    } on ApiException catch (error) {
      if (error.action == 'open_subscription') {
        Get.snackbar(
            'subscription.required.title'.tr, 'aiPets.subscriptionRequired'.tr);
        Get.toNamed('/subscription');
      } else {
        Get.snackbar('aiPets.error'.tr, error.message);
      }
    } finally {
      nameController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(leading: const VitaBackButton(), title: Text('aiPets.title'.tr)),
      body: _loading && _breeds.isEmpty
          ? ListView.builder(
              itemCount: 4,
              itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: true))
          : RefreshIndicator(
              onRefresh: _load,
              child: _breeds.isEmpty
                  ? ListView(children: [
                      SizedBox(
                          height: MediaQuery.sizeOf(context).height * .6,
                          child: VitaEmpty(
                              icon: Icons.pets_outlined,
                              title: 'aiPets.empty'.tr,
                              subtitle: 'aiPets.emptySub'.tr))
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      itemCount: _breeds.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _BreedCard(
                          breed: _breeds[index],
                          onTap: () => _openBreed(_breeds[index])),
                    ),
            ),
    );
  }
}

class _BreedCard extends StatelessWidget {
  const _BreedCard({required this.breed, required this.onTap});
  final Map<String, dynamic> breed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final adopted = '${breed['adopted_companion_id'] ?? ''}'.isNotEmpty;
    final allowed = breed['can_adopt'] == true;
    return VitaCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                    width: 76,
                    height: 76,
                    child: AIPetAvatar(
                        name: '${breed['name'] ?? ''}',
                        imageUrl: '${breed['avatar_url'] ?? ''}'))),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('${breed['name'] ?? ''}',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: context.vita.text)),
                  const SizedBox(height: 2),
                  Text(
                      '${breed['species'] ?? ''} · ${breed['personality'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: context.vita.subText)),
                  const SizedBox(height: 7),
                  Text('${breed['description'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          color: context.vita.text)),
                  const SizedBox(height: 8),
                  Text(
                      adopted
                          ? 'aiPets.adopted'.tr
                          : allowed
                              ? 'aiPets.available'.tr
                              : 'aiPets.planLocked'.tr,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: adopted || allowed
                              ? context.vita.green
                              : context.vita.subText)),
                ])),
            Icon(Icons.chevron_right, color: context.vita.chevron),
          ]),
        ),
      ),
    );
  }
}

class AIPetHomePage extends StatefulWidget {
  const AIPetHomePage(
      {super.key,
      required this.companionId,
      required this.name,
      required this.avatarUrl,
      required this.species});
  final String companionId;
  final String name;
  final String avatarUrl;
  final String species;

  @override
  State<AIPetHomePage> createState() => _AIPetHomePageState();
}

class _AIPetHomePageState extends State<AIPetHomePage> {
  Map<String, dynamic>? _state;
  bool _loading = true;
  bool _feeding = false;
  _PetAction _action = _PetAction.idle;
  Timer? _actionTimer;
  Timer? _ambientTimer;
  final math.Random _random = math.Random();

  Map<String, dynamic> get _companion => {
        'id': widget.companionId,
        'name': widget.name,
        'portrait_url': widget.avatarUrl,
        'occupation': widget.species,
        'creation_source': 'ai_pet',
        'friendship_active': true,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _actionTimer?.cancel();
    _ambientTimer?.cancel();
    super.dispose();
  }

  bool get _needsSleep => ((_state?['energy'] as num?)?.toInt() ?? 100) < 20;

  void _scheduleAmbientAction() {
    _ambientTimer?.cancel();
    if (!mounted || _feeding || _needsSleep) return;
    _ambientTimer = Timer(Duration(seconds: 3 + _random.nextInt(4)), () {
      if (!mounted || _feeding || _needsSleep) return;
      setState(() => _action = _PetAction.walking);
      _ambientTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted || _feeding) return;
        setState(() =>
            _action = _needsSleep ? _PetAction.sleeping : _PetAction.idle);
        _scheduleAmbientAction();
      });
    });
  }

  void _showAction(_PetAction action, {Duration? duration}) {
    _actionTimer?.cancel();
    _ambientTimer?.cancel();
    if (!mounted) return;
    setState(() => _action = action);
    if (duration != null) {
      _actionTimer = Timer(duration, () {
        if (!mounted) return;
        setState(() =>
            _action = _needsSleep ? _PetAction.sleeping : _PetAction.idle);
        _scheduleAmbientAction();
      });
    }
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance
          .get('/v1/ai-pets/${widget.companionId}/state');
      if (mounted && data is Map) {
        final nextState = Map<String, dynamic>.from(data);
        setState(() {
          _state = nextState;
          _action = ((nextState['energy'] as num?)?.toInt() ?? 100) < 20
              ? _PetAction.sleeping
              : _PetAction.idle;
        });
        _scheduleAmbientAction();
      }
    } on ApiException catch (error) {
      if (mounted) Get.snackbar('aiPets.error'.tr, error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _feed() async {
    if (_feeding) return;
    final previousLevel = (_state?['level'] as num?)?.toInt() ?? 1;
    final animationStartedAt = DateTime.now();
    setState(() {
      _feeding = true;
      _action = _PetAction.feeding;
    });
    try {
      final data = await ApiClient.instance
          .post('/v1/ai-pets/${widget.companionId}/feed', data: {
        'idempotency_key':
            'pet-feed-${widget.companionId}-${DateTime.now().microsecondsSinceEpoch}'
      });
      final animationElapsed = DateTime.now().difference(animationStartedAt);
      const minimumFeedingDuration = Duration(milliseconds: 1200);
      if (animationElapsed < minimumFeedingDuration) {
        await Future<void>.delayed(minimumFeedingDuration - animationElapsed);
      }
      final state = data is Map ? data['state'] : null;
      if (mounted && state is Map) {
        final nextState = Map<String, dynamic>.from(state);
        final nextLevel =
            (nextState['level'] as num?)?.toInt() ?? previousLevel;
        setState(() => _state = nextState);
        _showAction(
            nextLevel > previousLevel ? _PetAction.levelUp : _PetAction.happy,
            duration: const Duration(milliseconds: 1800));
      }
      Get.snackbar('aiPets.fed'.tr, 'aiPets.fedSub'.tr);
    } on ApiException catch (error) {
      _showAction(_PetAction.idle);
      if (error.code == 'insufficient_credits') {
        Get.snackbar('aiPets.notEnoughCoins'.tr, 'aiPets.notEnoughCoinsSub'.tr);
        Get.toNamed('/credits');
      } else {
        Get.snackbar('aiPets.error'.tr, error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _feeding = false);
        if (_action == _PetAction.idle) _scheduleAmbientAction();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state ?? const <String, dynamic>{};
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(leading: const VitaBackButton(), title: Text(widget.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  children: [
                    _AnimatedPetScene(
                        name: widget.name,
                        imageUrl: widget.avatarUrl,
                        action: _action,
                        onTap: () => _showAction(_PetAction.happy,
                            duration: const Duration(milliseconds: 1400))),
                    const SizedBox(height: 12),
                    VitaCard(
                        child: Column(children: [
                      Text(widget.name,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: context.vita.text)),
                      Text(
                          '${widget.species} · ${'aiPets.level'.trParams({
                                'level': '${state['level'] ?? 1}'
                              })}',
                          style: TextStyle(color: context.vita.subText)),
                      const SizedBox(height: 16),
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
                          color: context.vita.green),
                      const SizedBox(height: 8),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                'aiPets.experience'.trParams(
                                    {'value': '${state['experience'] ?? 0}'}),
                                style: TextStyle(color: context.vita.subText)),
                            Text(
                                'aiPets.coins'.trParams(
                                    {'value': '${state['coins'] ?? 0}'}),
                                style: TextStyle(color: context.vita.subText))
                          ]),
                      const SizedBox(height: 14),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                              onPressed: _feeding ? null : _feed,
                              icon: const Icon(Icons.restaurant),
                              label: Text(_feeding
                                  ? 'aiPets.feeding'.tr
                                  : 'aiPets.feed'.trParams({
                                      'coins': '${state['feed_coin_cost'] ?? 5}'
                                    })))),
                    ])),
                    const SizedBox(height: 12),
                    VitaCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(children: [
                          VitaListTile(
                              icon: Icons.chat_bubble_outline,
                              title: 'aiPets.chat'.tr,
                              onTap: () => Get.to(() => ChatPage(
                                  companionId: widget.companionId,
                                  name: widget.name,
                                  companion: _companion))),
                          VitaListTile(
                              icon: Icons.auto_stories_outlined,
                              title: 'aiPets.life'.tr,
                              onTap: () => Get.to(
                                  () => LifeDetailPage(companion: _companion))),
                          VitaListTile(
                              icon: Icons.star_border,
                              title: 'aiPets.memories'.tr,
                              onTap: () => Get.to(() =>
                                  MemoryDetailPage(companion: _companion))),
                        ])),
                  ]),
            ),
    );
  }
}

enum _PetAction { idle, walking, happy, feeding, sleeping, levelUp }

class _AnimatedPetScene extends StatefulWidget {
  const _AnimatedPetScene({
    required this.name,
    required this.imageUrl,
    required this.action,
    required this.onTap,
  });

  final String name;
  final String imageUrl;
  final _PetAction action;
  final VoidCallback onTap;

  @override
  State<_AnimatedPetScene> createState() => _AnimatedPetSceneState();
}

class _AnimatedPetSceneState extends State<_AnimatedPetScene>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _actionController;
  late final AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
    _actionController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850));
    _blinkController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4200))
      ..repeat();
    _syncActionAnimation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedPetScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action != widget.action) {
      _syncActionAnimation();
    }
  }

  void _syncActionAnimation() {
    switch (widget.action) {
      case _PetAction.walking:
        _actionController.duration = const Duration(milliseconds: 6000);
        _actionController.repeat();
        break;
      case _PetAction.feeding:
        _actionController.duration = const Duration(milliseconds: 560);
        _actionController.repeat();
        break;
      case _PetAction.happy:
      case _PetAction.levelUp:
        _actionController.duration = const Duration(milliseconds: 900);
        _actionController.repeat();
        break;
      case _PetAction.sleeping:
      case _PetAction.idle:
        _actionController.stop();
        _actionController.value = 0;
        break;
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _actionController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  double _blinkAmount(double progress) {
    if (progress < .86 || progress > .96) return 0;
    if (progress < .91) return (progress - .86) / .05;
    return 1 - ((progress - .91) / .05);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.name,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 330,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFE4CF), Color(0xFFFFF6E8)],
            ),
          ),
          child: Stack(children: [
            const Positioned(
                top: 28,
                left: 26,
                child: _SceneBubble(size: 64, color: Color(0x66FFFFFF))),
            const Positioned(
                top: 72,
                right: 28,
                child: _SceneBubble(size: 38, color: Color(0x55F6A96C))),
            Positioned(
              left: -30,
              right: -30,
              bottom: -48,
              child: Container(
                height: 135,
                decoration: const BoxDecoration(
                    color: Color(0xFFFFD7AE), shape: BoxShape.circle),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _idleController,
                  _actionController,
                  _blinkController,
                ]),
                builder: (context, _) {
                  final idle = math.sin(_idleController.value * math.pi * 2);
                  final cycle = _actionController.value;
                  final actionWave = math.sin(cycle * math.pi);
                  final repeatingWave = math.sin(cycle * math.pi * 2);
                  final blink = widget.action == _PetAction.sleeping
                      ? 1.0
                      : widget.action == _PetAction.feeding
                          ? 0.0
                          : _blinkAmount(_blinkController.value);
                  final hasBlinkFrame =
                      aiPetClosedEyeAssetPath(widget.imageUrl) != null;
                  var dy = idle * 4;
                  var dx = 0.0;
                  var scale = 1.0;
                  var scaleY = 1.0 - (hasBlinkFrame ? 0 : blink * .09);
                  var angle = 0.0;
                  var faceLeft = false;
                  switch (widget.action) {
                    case _PetAction.walking:
                      final travel = .5 - .5 * math.cos(cycle * math.pi * 2);
                      dx = -62 + travel * 124;
                      dy = -repeatingWave.abs() * 7;
                      angle = repeatingWave * .025;
                      scaleY -= repeatingWave.abs() * .025;
                      faceLeft = cycle >= .5;
                      break;
                    case _PetAction.happy:
                      dy -= actionWave.abs() * 24;
                      scale += actionWave * .06;
                      break;
                    case _PetAction.feeding:
                      dy += 28 + repeatingWave.abs() * 12;
                      angle = -.055 + repeatingWave * .018;
                      scaleY = .94 - repeatingWave.abs() * .035;
                      break;
                    case _PetAction.sleeping:
                      dy = 27 + idle * 2;
                      scale = .92 + idle * .008;
                      scaleY = .84 + idle * .012;
                      angle = -.075 + idle * .008;
                      break;
                    case _PetAction.levelUp:
                      dy -= actionWave.abs() * 18;
                      scale += actionWave.abs() * .12;
                      break;
                    case _PetAction.idle:
                      break;
                  }
                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: Transform.rotate(
                      angle: angle,
                      child: Transform.scale(
                        scaleX: (faceLeft ? -1.0 : 1.0) * scale,
                        scaleY: scale * scaleY,
                        alignment: const Alignment(0, .55),
                        child: Align(
                          alignment: const Alignment(0, .35),
                          child: SizedBox(
                            width: 245,
                            height: 245,
                            child: AIPetAvatar(
                              name: widget.name,
                              imageUrl: widget.imageUrl,
                              blinkAmount: blink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.action == _PetAction.happy)
              const Positioned(
                  top: 58,
                  right: 54,
                  child: Text('♥',
                      style:
                          TextStyle(fontSize: 42, color: Color(0xFFF06A89)))),
            if (widget.action == _PetAction.feeding)
              Positioned(
                  bottom: 15,
                  left: 0,
                  right: 0,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('🥣', style: TextStyle(fontSize: 56)),
                    Container(
                        width: 78,
                        height: 8,
                        decoration: BoxDecoration(
                            color: const Color(0x22000000),
                            borderRadius: BorderRadius.circular(100))),
                  ])),
            if (widget.action == _PetAction.sleeping)
              const Positioned(
                  top: 58,
                  right: 48,
                  child: Text('Zzz',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF776A9E)))),
            if (widget.action == _PetAction.levelUp) ...const [
              Positioned(top: 50, left: 48, child: _SceneStar()),
              Positioned(top: 78, right: 42, child: _SceneStar(size: 34)),
              Positioned(bottom: 82, right: 58, child: _SceneStar(size: 24)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _SceneBubble extends StatelessWidget {
  const _SceneBubble({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _SceneStar extends StatelessWidget {
  const _SceneStar({this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.star_rounded, size: size, color: const Color(0xFFFFB930));
}

class _StatusBar extends StatelessWidget {
  const _StatusBar(
      {required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          SizedBox(
              width: 70,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: context.vita.subText))),
          Expanded(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                      value: value.clamp(0, 100) / 100,
                      minHeight: 9,
                      backgroundColor: context.vita.pageBg,
                      valueColor: AlwaysStoppedAnimation(color)))),
          const SizedBox(width: 10),
          SizedBox(
              width: 28,
              child: Text('$value',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: context.vita.subText))),
        ]),
      );
}
