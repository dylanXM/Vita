import '../pet/pet_motion_spec.dart';
import 'pet_intent.dart';

/// AI 意图接口：动画层只消费 [PetIntent]，不感知 AI 来源。
/// 后续接入 SSE/WebSocket 事件流时，实现 [AIPetBrain] 即可，动画层零改动。
abstract class PetBrain {
  Stream<PetIntent> watch();
}

/// 本地意图实现：把服务器数值 + 用户操作映射为 [PetIntent]。
class LocalPetBrain implements PetBrain {
  /// 服务器状态 → 意图：
  /// energy<20 → sleeping；hunger<30 → hungry；happiness<30 → sick；
  /// energy<50 → tired；否则 standing。
  PetIntent intentFromState(Map<String, dynamic> state) {
    final energy = (state['energy'] as num?)?.toInt() ?? 100;
    final hunger = (state['hunger'] as num?)?.toInt() ?? 100;
    final happiness = (state['happiness'] as num?)?.toInt() ?? 100;
    if (energy < 20) {
      return const PetIntent(mood: PetMood.tired, state: PetState.sleeping);
    }
    if (hunger < 30) {
      return const PetIntent(mood: PetMood.sad, state: PetState.hungry);
    }
    if (happiness < 30) {
      return const PetIntent(mood: PetMood.sad, state: PetState.sick);
    }
    if (energy < 50) {
      return const PetIntent(mood: PetMood.tired, state: PetState.tired);
    }
    return const PetIntent(mood: PetMood.happy, state: PetState.standing);
  }

  @override
  Stream<PetIntent> watch() => const Stream.empty();
}
