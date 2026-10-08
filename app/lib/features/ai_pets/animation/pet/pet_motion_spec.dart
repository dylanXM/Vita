/// 宠物状态（数据驱动动画规格的键）。
enum PetState {
  idle,
  standing,
  sitting,
  walking,
  feeding,
  happy,
  sleeping,
  levelUp,
  thinking,
  tired,
  hungry,
  sick,
}

/// 状态附加特效。
enum PetFx { hearts, stars, sweat, notes, zzz, bowl, tired, hungry }

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
    // 站起：轻微呼吸起伏，2.6 秒一个周期。
    PetState.standing: PetMotionSpec(
      duration: Duration(milliseconds: 2600),
      repeat: true,
      driftY: 5,
    ),
    // 坐下：身体下沉，轻微摇摆。
    PetState.sitting: PetMotionSpec(
      duration: Duration(milliseconds: 2600),
      repeat: true,
      driftY: 2,
      sway: 0.02,
      squash: 0.06,
    ),
    PetState.idle: PetMotionSpec(
      duration: Duration(milliseconds: 2600),
      repeat: true,
      driftY: 5,
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
      scale: 1.06,
      fx: [PetFx.hearts],
    ),
    PetState.sleeping: PetMotionSpec(
      duration: Duration(milliseconds: 2600),
      repeat: true,
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
      scale: 1.12,
      fx: [PetFx.stars],
    ),
    PetState.thinking: PetMotionSpec(
      duration: Duration(milliseconds: 2200),
      repeat: true,
      driftY: 6,
      sway: 0.03,
      fx: [PetFx.notes],
    ),
    // 困：无精打采地下沉摇摆，头顶冒困意气泡。
    PetState.tired: PetMotionSpec(
      duration: Duration(milliseconds: 2600),
      repeat: true,
      driftY: 6,
      sway: 0.04,
      squash: 0.05,
      fx: [PetFx.tired],
    ),
    // 饿：垂头丧气，头顶飘小骨头。
    PetState.hungry: PetMotionSpec(
      duration: Duration(milliseconds: 2600),
      repeat: true,
      driftY: 6,
      sway: 0.03,
      fx: [PetFx.hungry],
    ),
    PetState.sick: PetMotionSpec(
      duration: Duration(milliseconds: 2200),
      repeat: true,
      driftY: 6,
      sway: 0.015,
      squash: 0.08,
      fx: [PetFx.sweat],
    ),
  };
}
