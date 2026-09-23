/// 宠物状态（数据驱动动画规格的键）。
enum PetState { idle, walking, feeding, happy, sleeping, levelUp, thinking, sick }

/// 状态附加特效。
enum PetFx { hearts, stars, sweat, notes, zzz, bowl }

/// 每个状态的动画规格：时长/是否循环/平移/弹跳/摇摆/压扁/缩放/特效。
class PetMotionSpec {
  const PetMotionSpec({
    this.duration = const Duration(milliseconds: 900),
    this.repeat = false,
    this.driftX = 0,
    this.driftY = 0,
    this.bounce = 0,
    this.sway = 0,
    this.squash = 0,
    this.scale = 1,
    this.fx = const [],
  });

  final Duration duration;
  final bool repeat;
  final double driftX; // 平移幅度（逻辑像素）
  final double driftY;
  final double bounce; // 垂直弹跳幅度
  final double sway; // 摇摆角度（弧度）
  final double squash; // 压扁幅度
  final double scale; // 基础缩放
  final List<PetFx> fx; // 附加特效

  static const Map<PetState, PetMotionSpec> table = {
    PetState.idle: PetMotionSpec(
      duration: Duration(milliseconds: 2200),
      driftY: 4,
    ),
    PetState.walking: PetMotionSpec(
      duration: Duration(milliseconds: 6000),
      repeat: true,
      driftX: 62,
      driftY: 7,
      sway: 0.025,
      squash: 0.025,
    ),
    PetState.feeding: PetMotionSpec(
      duration: Duration(milliseconds: 560),
      repeat: true,
      driftY: 28,
      sway: 0.055,
      squash: 0.035,
      fx: [PetFx.bowl],
    ),
    PetState.happy: PetMotionSpec(
      duration: Duration(milliseconds: 900),
      repeat: true,
      bounce: 24,
      scale: 0.06,
      fx: [PetFx.hearts],
    ),
    PetState.sleeping: PetMotionSpec(
      duration: Duration(milliseconds: 2200),
      driftY: 2,
      sway: 0.075,
      squash: 0.16,
      scale: 0.92,
      fx: [PetFx.zzz],
    ),
    PetState.levelUp: PetMotionSpec(
      duration: Duration(milliseconds: 900),
      repeat: true,
      bounce: 18,
      scale: 0.12,
      fx: [PetFx.stars],
    ),
    PetState.thinking: PetMotionSpec(
      duration: Duration(milliseconds: 2200),
      driftY: 6,
      sway: 0.03,
      fx: [PetFx.notes],
    ),
    PetState.sick: PetMotionSpec(
      duration: Duration(milliseconds: 2200),
      driftY: 6,
      sway: 0.015,
      squash: 0.08,
      fx: [PetFx.sweat],
    ),
  };
}
