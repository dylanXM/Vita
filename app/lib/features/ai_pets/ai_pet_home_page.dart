import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'animation/brain/pet_brain.dart';
import 'animation/pet/pet_motion_spec.dart';
import 'animation/pet/pet_state_machine.dart';
import 'animation/scene/pet_stage.dart';
import 'animation/scene/weather_particles.dart';
import 'animation/ui/pet_action_menu.dart';
import 'animation/world_clock.dart';
import 'ai_pet_desktop_controller.dart';
import 'ai_pet_avatar.dart';

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
  final Weather _weather = Weather.none;
  Timer? _vitalsTimer;
  bool _reduceMotion = false;

  String get _currentAvatarUrl {
    final saved = _state?['avatar_url'];
    return saved is String && saved.isNotEmpty ? saved : widget.avatarUrl;
  }

  String get _currentSpriteSheetUrl {
    final saved = _state?['sprite_sheet_url'];
    if (saved is String && saved.isNotEmpty) return saved;
    return aiPetPoseSheetAssetPath(_currentAvatarUrl) ?? '';
  }

  String get _currentActionSheetUrl {
    final saved = _state?['action_sheet_url'];
    if (saved is String && saved.isNotEmpty) return saved;
    return aiPetActionSheetAssetPath(_currentAvatarUrl) ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AIPetDesktopController.to.petHomeVisible.value = true;
    });
    AnalyticsService.to.track('ai_pet_home_viewed', category: 'companion');
    _worldClock = WorldClock(vsync: this);
    _machine = PetStateMachine(vsync: this);
    _load();
    // 只同步真实生命数值；不再随机安排吃喝或姿势。
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AIPetDesktopController.to.petHomeVisible.value = false;
    });
    _vitalsTimer?.cancel();
    _worldClock.dispose();
    _machine.dispose();
    super.dispose();
  }

  void _applyIntent(Map<String, dynamic> nextState, {bool silent = false}) {
    final intent = _brain.intentFromState(nextState);
    _machine.updateVitals(
      energy: (nextState['energy'] as num?)?.toInt() ?? 100,
      hunger: (nextState['hunger'] as num?)?.toInt() ?? 100,
      happiness: (nextState['happiness'] as num?)?.toInt() ?? 100,
    );
    // 数值轮询只更新需要，不打断当前的短动作或手动喂食。
    if (!_feeding && !_machine.isActionActive) {
      _machine.transition(intent.state);
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
      const minimumFeedingDuration = Duration(milliseconds: 2600);
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
      if (error.code == 'insufficient_credits') {
        Get.snackbar('aiPets.notEnoughCoins'.tr, 'aiPets.notEnoughCoinsSub'.tr);
        Get.toNamed('/credits');
      } else {
        Get.snackbar('aiPets.error'.tr, error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _feeding = false);
      }
    }
  }

  void _petTap() {
    if (_feeding) return;
    _machine.showAction(PetState.happy,
        duration: const Duration(milliseconds: 2000));
  }

  void _drink() {
    if (_feeding) return;
    _machine.showAction(PetState.drinking,
        duration: const Duration(milliseconds: 2800));
  }

  void _walk() {
    if (_feeding) return;
    _machine.showAction(PetState.walking,
        duration: const Duration(milliseconds: 6000));
  }

  void _sit() {
    if (_feeding) return;
    _machine.showAction(PetState.sitting,
        duration: const Duration(milliseconds: 4000));
  }

  void _rest() {
    if (_feeding) return;
    _machine.showAction(PetState.sleeping,
        duration: const Duration(milliseconds: 6000));
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
            imageUrl: _currentAvatarUrl,
            spriteSheetUrl: _currentSpriteSheetUrl,
            actionSheetUrl: _currentActionSheetUrl,
            machine: _machine,
            clock: _worldClock,
            weather: _weather,
            onTap: _petTap,
            onBack: () => Get.back(),
          ),
          // 右下角悬浮操作按钮（喂食/生活/刷新 + 状态面板）。
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
                onDrink: _drink,
                onWalk: _walk,
                onSit: _sit,
                onRest: _rest,
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
                  border: Border.all(color: context.vita.glassRing, width: .8),
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
