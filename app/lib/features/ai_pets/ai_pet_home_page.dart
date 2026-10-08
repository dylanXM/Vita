import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../chat/chat_page.dart';
import '../life/life_detail_page.dart';
import '../memories/memories_page.dart';
import 'animation/brain/pet_brain.dart';
import 'animation/pet/pet_motion_spec.dart';
import 'animation/pet/pet_state_machine.dart';
import 'animation/scene/pet_stage.dart';
import 'animation/scene/weather_particles.dart';
import 'animation/ui/pet_action_menu.dart';
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
  Timer? _vitalsTimer;
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
    // 周期性静默同步服务器数值，让宠物自主切换困/饿/睡等生活状态。
    _vitalsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _refreshState();
    });
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
    _vitalsTimer?.cancel();
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

  void _applyIntent(Map<String, dynamic> nextState, {bool silent = false}) {
    final intent = _brain.intentFromState(nextState);
    _machine.updateVitals(
      energy: (nextState['energy'] as num?)?.toInt() ?? 100,
      hunger: (nextState['hunger'] as num?)?.toInt() ?? 100,
      happiness: (nextState['happiness'] as num?)?.toInt() ?? 100,
    );
    // 进食中不打断动画。
    if (_machine.state != PetState.feeding) {
      _machine.transition(intent.state);
      _machine.scheduleAmbient();
    }
    if (!silent && mounted) setState(() => _state = nextState);
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance
          .get('/v1/ai-pets/${widget.companionId}/state');
      if (mounted && data is Map) {
        final nextState = Map<String, dynamic>.from(data);
        setState(() => _state = nextState);
        _applyIntent(nextState);
      }
    } on ApiException catch (error) {
      if (mounted) Get.snackbar('aiPets.error'.tr, error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 静默刷新数值：不展示加载态，只同步状态与生活动画。
  Future<void> _refreshState() async {
    try {
      final data = await ApiClient.instance
          .get('/v1/ai-pets/${widget.companionId}/state');
      if (mounted && data is Map) {
        final nextState = Map<String, dynamic>.from(data);
        setState(() => _state = nextState);
        _applyIntent(nextState, silent: true);
      }
    } on ApiException {
      // 静默失败，下次轮询重试。
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
        _machine.updateVitals(
          energy: (nextState['energy'] as num?)?.toInt() ?? 100,
          hunger: (nextState['hunger'] as num?)?.toInt() ?? 100,
          happiness: (nextState['happiness'] as num?)?.toInt() ?? 100,
        );
        _machine.showAction(
            nextLevel > previousLevel ? PetState.levelUp : PetState.happy,
            duration: const Duration(milliseconds: 1800));
      }
      Get.snackbar('aiPets.fed'.tr, 'aiPets.fedSub'.tr);
    } on ApiException catch (error) {
      _machine.transition(
          _machine.needsSleep ? PetState.sleeping : PetState.standing);
      _machine.scheduleAmbient();
      if (error.code == 'insufficient_credits') {
        Get.snackbar('aiPets.notEnoughCoins'.tr, 'aiPets.notEnoughCoinsSub'.tr);
        Get.toNamed('/credits');
      } else {
        Get.snackbar('aiPets.error'.tr, error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _feeding = false);
        if (_machine.state == PetState.standing ||
            _machine.state == PetState.idle) {
          _machine.scheduleAmbient();
        }
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
    final level = (state['level'] as num?)?.toInt() ?? 1;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PetStage(
            name: widget.name,
            species: widget.species,
            level: level,
            imageUrl: widget.avatarUrl,
            machine: _machine,
            clock: _worldClock,
            weather: _weather,
            onTap: _petTap,
            onBack: () => Get.back(),
          ),
          // 右下角悬浮操作按钮（喂食/聊天/生活/回忆/刷新 + 状态面板）。
          SafeArea(
            child: Align(
              alignment: const Alignment(.92, .98),
              child: PetActionMenu(
                level: level,
                coins: (state['coins'] as num?)?.toInt() ?? 0,
                experience: (state['experience'] as num?)?.toInt() ?? 0,
                state: state,
                feeding: _feeding,
                feedCost: (state['feed_coin_cost'] as num?)?.toInt() ?? 5,
                onFeed: _feed,
                onChat: () => Get.to(() => ChatPage(
                    companionId: widget.companionId,
                    name: widget.name,
                    companion: _companion)),
                onLife: () =>
                    Get.to(() => LifeDetailPage(companion: _companion)),
                onMemories: () =>
                    Get.to(() => MemoryDetailPage(companion: _companion)),
                onRefresh: _refreshState,
              ),
            ),
          ),
          if (_loading)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.vita.glass,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: context.vita.glassRing, width: .8),
                ),
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: context.vita.green),
              ),
            ),
        ],
      ),
    );
  }
}
