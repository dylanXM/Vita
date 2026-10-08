import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'pet_motion_spec.dart';

/// 宠物状态机：管理状态迁移、环境定时与动作动画。
/// 只消费 PetIntent/服务器数值，不感知 AI 来源。
///
/// 连贯性设计：所有状态都驱动在同一个循环时钟 [_motion] 上，状态切换时不重置
/// 相位；同时用 [_blend]（320ms）把「旧姿态 → 新姿态」插值过渡，渲染层再对
/// 姿态做线性混合，因此肉眼观察不到跳变。
class PetStateMachine extends ChangeNotifier {
  PetStateMachine({required TickerProvider vsync})
      : _motion = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 2600),
        ),
        _blend = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 320),
        );

  /// 循环姿态时钟：所有状态的相位共用这一个时钟，保证切换连续。
  final AnimationController _motion;

  /// 状态过渡混合：0 → 1，驱动新旧姿态插值。
  final AnimationController _blend;

  PetState _state = PetState.standing;
  PetState _previous = PetState.standing;
  bool needsSleep = false;
  bool needsFood = false;
  bool needsRest = false;
  bool reducedMotion = false;
  Timer? _ambientTimer;
  Timer? _actionTimer;
  final math.Random _random = math.Random();

  PetState get state => _state;

  /// 过渡开始前的状态（渲染层用它做姿态插值）。
  PetState get previous => _previous;

  AnimationController get controller => _motion;

  /// 当前过渡进度 0..1（已缓动），无过渡时为 1。
  double get blendValue => _blend.isAnimating || _blend.value > 0
      ? Curves.easeInOutCubic.transform(_blend.value)
      : 1;

  bool get _locked => _state == PetState.feeding;

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
  void updateVitals({required int energy, required int hunger, required int happiness}) {
    needsSleep = energy < 20;
    needsFood = hunger < 30;
    needsRest = energy < 50;
  }

  /// 直接迁移到 [next]：记录前序状态并启动平滑过渡，取消所有定时。
  void transition(PetState next) {
    if (next == _state) return;
    _actionTimer?.cancel();
    _ambientTimer?.cancel();
    _previous = _state;
    _state = next;
    _applySpec();
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
    _previous = _state;
    _state = action;
    _applySpec();
    if (reducedMotion) {
      _blend.value = 1;
    } else {
      _blend.forward(from: 0);
    }
    notifyListeners();
    if (duration != null) {
      _actionTimer = Timer(duration, () {
        if (_state != action) return;
        _previous = _state;
        _state = _fallback;
        _applySpec();
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
    if (_locked || needsSleep) return;
    _ambientTimer = Timer(_nextLifeDelay(), () {
      if (_locked || needsSleep || !hasListeners) return;
      _previous = _state;
      _state = _nextLifeState();
      _applySpec();
      if (reducedMotion) {
        _blend.value = 1;
      } else {
        _blend.forward(from: 0);
      }
      notifyListeners();
      scheduleAmbient();
    });
  }

  Duration _nextLifeDelay() {
    final seconds = switch (_state) {
      PetState.walking => 5 + _random.nextInt(4),
      PetState.sitting => 3 + _random.nextInt(5),
      PetState.tired => 3 + _random.nextInt(3),
      PetState.hungry => 3 + _random.nextInt(3),
      _ => 4 + _random.nextInt(5),
    };
    return Duration(seconds: seconds);
  }

  PetState _nextLifeState() {
    // 数值越差，困 / 饿越容易被触发。
    if (needsFood && _random.nextDouble() < .8) return PetState.hungry;
    if (needsRest && _random.nextDouble() < .8) return PetState.tired;
    final roll = _random.nextDouble();
    return switch (_state) {
      PetState.walking => roll < .5 ? PetState.standing : PetState.sitting,
      PetState.sitting =>
        roll < .6 ? PetState.standing : PetState.walking,
      PetState.tired || PetState.hungry =>
        roll < .5 ? PetState.standing : PetState.sitting,
      _ => roll < .42
          ? PetState.sitting
          : roll < .7
              ? PetState.walking
              : PetState.standing,
    };
  }

  void _applySpec() {
    final spec = PetMotionSpec.table[_state]!;
    _motion.duration = spec.duration;
    if (spec.repeat && !reducedMotion) {
      // 不重置相位：从当前值继续循环，切换瞬间保持连贯。
      _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void dispose() {
    _ambientTimer?.cancel();
    _actionTimer?.cancel();
    _motion.dispose();
    _blend.dispose();
    super.dispose();
  }
}
