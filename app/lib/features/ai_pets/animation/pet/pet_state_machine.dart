import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'pet_motion_spec.dart';

/// 宠物状态机：管理状态迁移、环境定时与动作动画。
/// 只消费 PetIntent/服务器数值，不感知 AI 来源。
class PetStateMachine extends ChangeNotifier {
  PetStateMachine({required TickerProvider vsync})
      : _controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 900),
        );

  final AnimationController _controller;
  PetState _state = PetState.idle;
  bool needsSleep = false;
  bool reducedMotion = false;
  Timer? _ambientTimer;
  Timer? _actionTimer;
  final math.Random _random = math.Random();

  PetState get state => _state;

  AnimationController get controller => _controller;

  PetState get _fallback =>
      needsSleep ? PetState.sleeping : PetState.idle;

  /// 依据服务器数值得出建议状态：energy<20 → sleeping，happiness<30 → sick。
  PetState suggestFromState(Map<String, dynamic> state) {
    final energy = (state['energy'] as num?)?.toInt() ?? 100;
    final happiness = (state['happiness'] as num?)?.toInt() ?? 100;
    needsSleep = energy < 20;
    if (needsSleep) return PetState.sleeping;
    if (happiness < 30) return PetState.sick;
    return PetState.idle;
  }

  /// 直接迁移到 [next]，取消所有定时。
  void transition(PetState next) {
    _actionTimer?.cancel();
    _ambientTimer?.cancel();
    _state = next;
    _applySpec();
    notifyListeners();
  }

  /// 执行某个动作；[duration] 后回落 idle/sleeping 并重新安排环境动画。
  void showAction(PetState action, {Duration? duration}) {
    _actionTimer?.cancel();
    _ambientTimer?.cancel();
    _state = action;
    _applySpec();
    notifyListeners();
    if (duration != null) {
      _actionTimer = Timer(duration, () {
        _state = _fallback;
        _applySpec();
        notifyListeners();
        scheduleAmbient();
      });
    }
  }

  /// 环境动画：3~7 秒后开始散步，走 6 秒后回落并继续循环。
  void scheduleAmbient() {
    _ambientTimer?.cancel();
    if (_state == PetState.feeding || needsSleep) return;
    _ambientTimer = Timer(Duration(seconds: 3 + _random.nextInt(4)), () {
      if (_state == PetState.feeding || needsSleep) return;
      _state = PetState.walking;
      _applySpec();
      notifyListeners();
      _ambientTimer = Timer(const Duration(seconds: 6), () {
        if (_state == PetState.feeding) return;
        _state = _fallback;
        _applySpec();
        notifyListeners();
        scheduleAmbient();
      });
    });
  }

  void _applySpec() {
    final spec = PetMotionSpec.table[_state]!;
    _controller.duration = spec.duration;
    if (spec.repeat && !reducedMotion) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _ambientTimer?.cancel();
    _actionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }
}
