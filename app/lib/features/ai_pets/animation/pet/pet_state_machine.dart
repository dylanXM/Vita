import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'pet_motion_spec.dart';

/// 宠物状态机：管理状态迁移、环境定时与动作动画。
/// 只消费 PetIntent/服务器数值，不感知 AI 来源。
///
/// 周期姿态由 WorldClock 驱动；600ms 过渡从当前混合姿态出发，可连续打断。
class PetStateMachine extends ChangeNotifier {
  PetStateMachine({required TickerProvider vsync})
      : _blend = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 600),
        ) {
    _blend.addListener(notifyListeners);
  }

  /// 状态过渡混合：0 → 1，驱动新旧姿态插值。
  final AnimationController _blend;

  PetState _state = PetState.standing;
  Map<PetState, double> _fromWeights = {PetState.standing: 1};
  bool needsSleep = false;
  bool needsFood = false;
  bool needsRest = false;
  bool _reducedMotion = false;
  Timer? _ambientTimer;
  Timer? _actionTimer;
  final math.Random _random = math.Random();

  PetState get state => _state;
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

  bool get _locked => isActionActive || _state == PetState.feeding;

  PetState get _fallback => needsSleep ? PetState.sleeping : PetState.standing;

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
  }

  /// 直接迁移到 [next]：记录前序状态并启动平滑过渡，取消所有定时。
  void transition(PetState next) {
    if (next == _state) return;
    _actionTimer?.cancel();
    _ambientTimer?.cancel();
    _fromWeights = stateWeights;
    _state = next;
    if (reducedMotion) {
      _blend.value = 1;
    } else {
      _blend.forward(from: 0);
    }
    notifyListeners();
  }

  /// 执行某个动作；[duration] 后平滑回落站立/睡觉并重新安排生活动画。
  void showAction(PetState action, {Duration? duration}) {
    _actionTimer?.cancel();
    _ambientTimer?.cancel();
    _fromWeights = stateWeights;
    _state = action;
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
        if (reducedMotion) {
          _blend.value = 1;
        } else {
          _blend.forward(from: 0);
        }
        notifyListeners();
        scheduleAmbient();
      });
    }
  }

  /// 生活状态调度：宠物在「站起 → 坐下 → 散步 → …」间自然地生活，
  /// 并根据数值穿插困 / 饿 / 睡。
  void scheduleAmbient() {
    _ambientTimer?.cancel();
    if (_locked) return;
    _ambientTimer = Timer(_nextLifeDelay(), () {
      if (_locked || !hasListeners) return;
      if (needsSleep) {
        // Low server energy must not freeze the character indefinitely.
        // It rests most of the time, with brief wakeful moments.
        final action =
            _random.nextBool() ? PetState.sitting : PetState.drinking;
        showAction(action, duration: const Duration(milliseconds: 2600));
        return;
      }
      final next = _nextLifeState();
      if (next == PetState.feeding || next == PetState.drinking) {
        showAction(next, duration: const Duration(milliseconds: 2600));
        return;
      }
      if (next == PetState.sleeping) {
        showAction(next, duration: const Duration(milliseconds: 5200));
        return;
      }
      transition(next);
      scheduleAmbient();
    });
  }

  Duration _nextLifeDelay() {
    final seconds = switch (_state) {
      PetState.walking => 5 + _random.nextInt(4),
      PetState.sitting => 3 + _random.nextInt(5),
      PetState.tired => 3 + _random.nextInt(3),
      PetState.hungry => 3 + _random.nextInt(3),
      PetState.drinking => 4 + _random.nextInt(3),
      _ => 4 + _random.nextInt(5),
    };
    return Duration(seconds: seconds);
  }

  PetState _nextLifeState() {
    // 数值越差，困 / 饿越容易被触发。
    if (needsFood && _random.nextDouble() < .55) return PetState.feeding;
    if (needsFood && _random.nextDouble() < .6) return PetState.hungry;
    if (needsRest && _random.nextDouble() < .8) return PetState.tired;
    final roll = _random.nextDouble();
    if (roll < .08) return PetState.sleeping;
    if (roll < .22) return PetState.drinking;
    return switch (_state) {
      PetState.walking => roll < .5 ? PetState.standing : PetState.sitting,
      PetState.sitting => roll < .6 ? PetState.standing : PetState.walking,
      PetState.tired ||
      PetState.hungry =>
        roll < .5 ? PetState.standing : PetState.sitting,
      _ => roll < .45
          ? PetState.sitting
          : roll < .78
              ? PetState.walking
              : PetState.standing,
    };
  }

  @override
  void dispose() {
    _ambientTimer?.cancel();
    _actionTimer?.cancel();
    _blend.dispose();
    super.dispose();
  }
}
