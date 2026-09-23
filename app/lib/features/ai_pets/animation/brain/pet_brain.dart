import '../pet/pet_motion_spec.dart';
import 'pet_intent.dart';

/// AI 意图接口：动画层只消费 [PetIntent]，不感知 AI 来源。
/// 后续接入 SSE/WebSocket 事件流时，实现 [AIPetBrain] 即可，动画层零改动。
abstract class PetBrain {
  Stream<PetIntent> watch();
}

/// 本地意图实现：把服务器数值 + 用户操作映射为 [PetIntent]。
class LocalPetBrain implements PetBrain {
  /// 服务器状态 → 意图（energy<20 → sleeping，happiness<30 → sick）。
  PetIntent intentFromState(Map<String, dynamic> state) {
    final energy = (state['energy'] as num?)?.toInt() ?? 100;
    final happiness = (state['happiness'] as num?)?.toInt() ?? 100;
    if (energy < 20) {
      return const PetIntent(mood: PetMood.tired, state: PetState.sleeping);
    }
    if (happiness < 30) {
      return const PetIntent(mood: PetMood.sad, state: PetState.sick);
    }
    return const PetIntent(mood: PetMood.happy, state: PetState.idle);
  }

  @override
  Stream<PetIntent> watch() => const Stream.empty();
}
