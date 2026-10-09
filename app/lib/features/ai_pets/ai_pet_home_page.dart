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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Map<String, dynamic>? _state;
  bool _loading = true;
  bool _feeding = false;
  bool _caring = false;
  DateTime? _lastPetSavedAt;
  final Map<String, String> _pendingCareKeys = {};
  int _stateRequestId = 0;
  late final WorldClock _worldClock;
  late final PetStateMachine _machine;
  final LocalPetBrain _brain = LocalPetBrain();
  final PetAmbientBehavior _ambientBehavior = const PetAmbientBehavior();
  final Weather _weather = Weather.none;
  Timer? _vitalsTimer;
  Timer? _ambientTimer;
  int _ambientTurn = 0;
  DateTime _lastInteractionAt = DateTime.now();
  bool _isForeground = true;
  bool _reduceMotion = false;

  String get _currentAvatarUrl {
    final saved = _state?['avatar_url'];
    return saved is String && saved.isNotEmpty ? saved : widget.avatarUrl;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AIPetDesktopController.to.petHomeVisible.value = true;
    });
    AnalyticsService.to.track('ai_pet_home_viewed', category: 'companion');
    _worldClock = WorldClock(vsync: this);
    _machine = PetStateMachine(vsync: this);
    _load();
    // 只同步真实生命数值；自主动作不会伪造喂食等照护结果。
    _vitalsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted ||
          !_isForeground ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      _refreshState();
    });
    _ambientTimer = Timer.periodic(const Duration(seconds: 14), (_) {
      if (!mounted ||
          !_isForeground ||
          ModalRoute.of(context)?.isCurrent == false ||
          _reduceMotion ||
          _feeding ||
          _caring ||
          _machine.isActionActive ||
          _machine.state != PetState.standing ||
          DateTime.now().difference(_lastInteractionAt) <
              const Duration(seconds: 12)) {
        return;
      }
      final vitals = _state;
      if (vitals == null) return;
      final action =
          _ambientBehavior.next(turn: _ambientTurn++, vitals: vitals);
      if (action != null) {
        _machine.showAction(action, duration: const Duration(seconds: 5));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (!_isForeground) {
      _worldClock.pause();
    } else {
      if (!_reduceMotion) _worldClock.resume();
      _refreshState();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AIPetDesktopController.to.petHomeVisible.value = false;
    });
    _vitalsTimer?.cancel();
    _ambientTimer?.cancel();
    _worldClock.dispose();
    _machine.dispose();
    super.dispose();
  }

  void _applyIntent(Map<String, dynamic> nextState, {bool silent = false}) {
    final intent = _brain.intentFromState(nextState);
    _machine.updateVitals(
      energy: (nextState['energy'] as num?)?.toInt() ?? 100,
      hunger: (nextState['hunger'] as num?)?.toInt() ?? 100,
      hydration: (nextState['hydration'] as num?)?.toInt() ?? 100,
      happiness: (nextState['happiness'] as num?)?.toInt() ?? 100,
    );
    // 数值轮询只更新需要，不打断当前的短动作或手动喂食。
    if (!_feeding && !_machine.isActionActive) {
      _machine.transition(intent.state);
    }
    if (!silent && mounted) setState(() => _state = nextState);
  }

  Future<void> _load() async {
    final requestId = ++_stateRequestId;
    try {
      final data = await ApiClient.instance
          .get('/v1/ai-pets/${widget.companionId}/state');
      if (mounted && requestId == _stateRequestId && data is Map) {
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
    if (_feeding || _caring) return;
    final requestId = ++_stateRequestId;
    try {
      final data = await ApiClient.instance
          .get('/v1/ai-pets/${widget.companionId}/state');
      if (mounted && requestId == _stateRequestId && data is Map) {
        final nextState = Map<String, dynamic>.from(data);
        setState(() => _state = nextState);
        _applyIntent(nextState, silent: true);
      }
    } on ApiException {
      // 静默失败，下次轮询重试。
    }
  }

  Future<void> _feed() async {
    if (_feeding || _caring) return;
    ++_stateRequestId;
    _lastInteractionAt = DateTime.now();
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
        ++_stateRequestId;
        final nextState = Map<String, dynamic>.from(state);
        final nextLevel =
            (nextState['level'] as num?)?.toInt() ?? previousLevel;
        setState(() => _state = nextState);
        _machine.updateVitals(
          energy: (nextState['energy'] as num?)?.toInt() ?? 100,
          hunger: (nextState['hunger'] as num?)?.toInt() ?? 100,
          hydration: (nextState['hydration'] as num?)?.toInt() ?? 100,
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
    if (_feeding || _caring) return;
    _lastInteractionAt = DateTime.now();
    final lastSaved = _lastPetSavedAt;
    if (lastSaved != null &&
        DateTime.now().difference(lastSaved) < const Duration(minutes: 5)) {
      _machine.showAction(PetState.happy,
          duration: const Duration(milliseconds: 2000));
      return;
    }
    _care('pet', PetState.happy, const Duration(milliseconds: 2000));
  }

  Future<void> _care(String kind, PetState action, Duration duration) async {
    if (_feeding || _caring) return;
    ++_stateRequestId;
    _lastInteractionAt = DateTime.now();
    setState(() => _caring = true);
    _machine.showAction(action, duration: duration);
    final requestKey = _pendingCareKeys.putIfAbsent(
      kind,
      () =>
          'pet-$kind-${widget.companionId}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      final data = await ApiClient.instance.post(
        '/v1/ai-pets/${widget.companionId}/care',
        data: {
          'kind': kind,
          'idempotency_key': requestKey,
        },
      );
      _pendingCareKeys.remove(kind);
      final state = data is Map ? data['state'] : null;
      if (mounted && state is Map) {
        ++_stateRequestId;
        final nextState = Map<String, dynamic>.from(state);
        setState(() => _state = nextState);
        _applyIntent(nextState, silent: true);
        if (kind == 'pet') _lastPetSavedAt = DateTime.now();
      }
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) {
        _pendingCareKeys.remove(kind);
      }
      if (mounted) {
        final message = switch (error.code) {
          'pet_care_cooldown' => 'aiPets.careCooldown'.tr,
          'pet_needs_rest' => 'aiPets.needsRest'.tr,
          _ => error.message,
        };
        Get.snackbar('aiPets.error'.tr, message);
      }
      _machine.transition(_machine.suggestFromState(_state ?? const {}));
    } catch (_) {
      if (mounted) Get.snackbar('aiPets.error'.tr, 'common.loadFailed'.tr);
      _machine.transition(_machine.suggestFromState(_state ?? const {}));
    } finally {
      if (mounted) setState(() => _caring = false);
    }
  }

  void _drink() {
    _care('drink', PetState.drinking, const Duration(milliseconds: 2800));
  }

  void _walk() {
    _care('walk', PetState.walking, const Duration(milliseconds: 6000));
  }

  void _sit() {
    if (_feeding || _caring) return;
    _lastInteractionAt = DateTime.now();
    _machine.showAction(PetState.sitting,
        duration: const Duration(milliseconds: 4000));
  }

  void _rest() {
    _care('rest', PetState.sleeping, const Duration(milliseconds: 6000));
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
            imageUrl: _currentAvatarUrl,
            spriteSheetUrl: _state?['sprite_sheet_url'] as String? ?? '',
            actionSheetUrl: _state?['action_sheet_url'] as String? ?? '',
            machine: _machine,
            clock: _worldClock,
            weather: _weather,
            onTap: _petTap,
            onLook: _machine.lookAt,
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
                busy: _feeding || _caring,
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
