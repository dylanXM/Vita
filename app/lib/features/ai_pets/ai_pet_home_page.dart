import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../chat/chat_page.dart';
import '../life/life_detail_page.dart';
import '../memories/memories_page.dart';
import 'animation/brain/pet_brain.dart';
import 'animation/pet/pet_motion_spec.dart';
import 'animation/pet/pet_state_machine.dart';
import 'animation/scene/pet_scene.dart';
import 'animation/scene/weather_particles.dart';
import 'animation/world_clock.dart';

class AIPetHomePage extends StatefulWidget {
  const AIPetHomePage({
    super.key,
    required this.companionId,
    required this.name,
    required this.avatarUrl,
    required this.species,
  });

  final String companionId;
  final String name;
  final String avatarUrl;
  final String species;

  @override
  State<AIPetHomePage> createState() => _AIPetHomePageState();
}

class _AIPetHomePageState extends State<AIPetHomePage>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _state;
  bool _loading = true;
  bool _feeding = false;
  late final WorldClock _worldClock;
  late final PetStateMachine _machine;
  final LocalPetBrain _brain = LocalPetBrain();
  Weather _weather = Weather.none;
  Timer? _weatherTimer;
  final math.Random _random = math.Random();
  bool _reduceMotion = false;

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
    AnalyticsService.to.track('ai_pet_home_viewed', category: 'companion');
    _worldClock = WorldClock(vsync: this);
    _machine = PetStateMachine(vsync: this);
    _load();
    _scheduleWeather();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
      _machine.reducedMotion = reduceMotion;
      if (reduceMotion) {
        _worldClock.pause();
      } else {
        _worldClock.resume();
      }
    }
  }

  @override
  void dispose() {
    _weatherTimer?.cancel();
    _worldClock.dispose();
    _machine.dispose();
    super.dispose();
  }

  void _scheduleWeather() {
    _weatherTimer?.cancel();
    _weatherTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {
        _weather = _reduceMotion
            ? Weather.none
            : Weather.values[_random.nextInt(Weather.values.length)];
      });
    });
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance
          .get('/v1/ai-pets/${widget.companionId}/state');
      if (mounted && data is Map) {
        final nextState = Map<String, dynamic>.from(data);
        final intent = _brain.intentFromState(nextState);
        setState(() {
          _state = nextState;
          _machine.needsSleep = intent.state == PetState.sleeping;
          _machine.transition(intent.state);
        });
        _machine.scheduleAmbient();
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
      _machine.transition(PetState.feeding);
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
        _machine.showAction(
            nextLevel > previousLevel ? PetState.levelUp : PetState.happy,
            duration: const Duration(milliseconds: 1800));
      }
      Get.snackbar('aiPets.fed'.tr, 'aiPets.fedSub'.tr);
    } on ApiException catch (error) {
      _machine.transition(
          _machine.needsSleep ? PetState.sleeping : PetState.idle);
      if (error.code == 'insufficient_credits') {
        Get.snackbar('aiPets.notEnoughCoins'.tr, 'aiPets.notEnoughCoinsSub'.tr);
        Get.toNamed('/credits');
      } else {
        Get.snackbar('aiPets.error'.tr, error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _feeding = false);
        if (_machine.state == PetState.idle) _machine.scheduleAmbient();
      }
    }
  }

  void _petTap() {
    _machine.showAction(PetState.happy,
        duration: const Duration(milliseconds: 1400));
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
                  PetScene(
                    name: widget.name,
                    imageUrl: widget.avatarUrl,
                    machine: _machine,
                    worldClock: _worldClock,
                    weather: _weather,
                    onTap: _petTap,
                  ),
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
                ],
              ),
            ),
    );
  }
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
