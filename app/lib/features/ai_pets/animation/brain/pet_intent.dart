import '../pet/pet_motion_spec.dart';

/// 情绪类型。
enum PetMood { happy, sad, tired, excited }

/// 动画意图：AI/服务器事件 → 动画层消费的唯一入口。
class PetIntent {
  const PetIntent({
    required this.mood,
    required this.state,
    this.speech,
  });

  final PetMood mood;
  final PetState state;

  /// AI 说的话 → 宠物气泡。
  final String? speech;
}
