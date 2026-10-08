import 'dart:async';

import 'package:flutter/widgets.dart';

import 'pet_motion_spec.dart';

/// 宠物状态机：根据真实数值和用户互动管理状态迁移与动作动画。
/// 只消费 PetIntent/服务器数值，不感知 AI 来源。
///
/// 周期姿态由 WorldClock 驱动；420ms 过渡从当前混合姿态出发，可连续打断。
class PetStateMachine extends ChangeNotifier {
  static const transitionDuration = Duration(milliseconds: 420);

  PetStateMachine({required TickerProvider vsync})
      : _blend = AnimationController(
          vsync: vsync,
          duration: transitionDuration,
        ) {
    _blend.addListener(notifyListeners);
  }

  /// 状态过渡混合：0 → 1，驱动新旧姿态插值。
  final AnimationController _blend;

  PetState _state = PetState.standing;
  DateTime _stateChangedAt = DateTime.now();
  Map<PetState, double> _fromWeights = {PetState.standing: 1};
  bool needsSleep = false;
  bool needsFood = false;
  bool needsRest = false;
  bool needsCare = false;
  bool _reducedMotion = false;
  Timer? _actionTimer;

  PetState get state => _state;
  Duration get stateElapsed => DateTime.now().difference(_stateChangedAt);
  bool get isActionActive => _actionTimer?.isActive == true;

  bool get reducedMotion => _reducedMotion;
  set reducedMotion(bool value) {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    if (value) {
      _blend.value = 1;
    }
    notifyListeners();
  }

  /// 当前过渡进度 0..1（已缓动），无过渡时为 1。
  double get blendValue => Curves.easeInOutSine.transform(_blend.value);

  /// State weights at this exact frame. A new transition starts from the
  /// already blended pose, so interrupting a transition cannot snap back.
  Map<PetState, double> get stateWeights {
    final blend = blendValue;
    final weights = <PetState, double>{};
    for (final entry in _fromWeights.entries) {
      final weight = entry.value * (1 - blend);
      if (weight > 0) weights[entry.key] = weight;
    }
    weights[_state] = (weights[_state] ?? 0) + blend;
    return weights;
  }

  double weightFor(PetState state) => stateWeights[state] ?? 0;

  PetState get _fallback => needsSleep
      ? PetState.sleeping
      : needsFood
          ? PetState.hungry
          : needsCare
              ? PetState.sick
              : needsRest
                  ? PetState.tired
                  : PetState.standing;

  /// 依据服务器数值得出建议状态：
  /// energy<20 → sleeping；hunger<30 → hungry；happiness<30 → sick；
  /// energy<50 → tired；否则 standing。
  PetState suggestFromState(Map<String, dynamic> state) {
    final energy = (state['energy'] as num?)?.toInt() ?? 100;
    final hunger = (state['hunger'] as num?)?.toInt() ?? 100;
    final happiness = (state['happiness'] as num?)?.toInt() ?? 100;
    updateVitals(energy: energy, hunger: hunger, happiness: happiness);
    if (needsSleep) return PetState.sleeping;
    if (needsFood) return PetState.hungry;
    if (happiness < 30) return PetState.sick;
    if (needsRest) return PetState.tired;
    return PetState.standing;
  }

  /// 刷新生命数值：同步「困 / 饿 / 要睡觉」标志。
  /// 状态切换由调用方根据 [suggestFromState] 驱动。
  void updateVitals(
      {required int energy, required int hunger, required int happiness}) {
    needsSleep = energy < 20;
    needsFood = hunger < 30;
    needsRest = energy < 50;
    needsCare = happiness < 30;
  }

  /// 直接迁移到 [next]：记录前序状态并启动平滑过渡。
  void transition(PetState next) {
    if (next == _state) return;
    _actionTimer?.cancel();
    _fromWeights = stateWeights;
    _state = next;
    _stateChangedAt = DateTime.now();
    if (reducedMotion) {
      _blend.value = 1;
    } else {
      _blend.forward(from: 0);
    }
    notifyListeners();
  }

  /// 执行某个动作；[duration] 后平滑回落到生命数值对应的稳定状态。
  void showAction(PetState action, {Duration? duration}) {
    _actionTimer?.cancel();
    _fromWeights = stateWeights;
    _state = action;
    _stateChangedAt = DateTime.now();
    if (reducedMotion) {
      _blend.value = 1;
    } else {
      _blend.forward(from: 0);
    }
    notifyListeners();
    if (duration != null) {
      _actionTimer = Timer(duration, () {
        if (_state != action) return;
        _fromWeights = stateWeights;
        _state = _fallback;
        _stateChangedAt = DateTime.now();
        if (reducedMotion) {
          _blend.value = 1;
        } else {
          _blend.forward(from: 0);
        }
        notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _actionTimer?.cancel();
    _blend.dispose();
    super.dispose();
  }
}
