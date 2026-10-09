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
    final hydration = (state['hydration'] as num?)?.toInt() ?? 100;
    final happiness = (state['happiness'] as num?)?.toInt() ?? 100;
    if (energy < 20) {
      return const PetIntent(mood: PetMood.tired, state: PetState.sleeping);
    }
    if (hunger < 30) {
      return const PetIntent(mood: PetMood.sad, state: PetState.hungry);
    }
    if (hydration < 30) {
      return const PetIntent(mood: PetMood.sad, state: PetState.sick);
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

/// Low-frequency, non-care actions for a healthy pet. These do not change
/// server vitals or pretend that food, water, or rest was provided.
class PetAmbientBehavior {
  const PetAmbientBehavior();

  PetState? next({required int turn, required Map<String, dynamic> vitals}) {
    final energy = (vitals['energy'] as num?)?.toInt() ?? 100;
    final hunger = (vitals['hunger'] as num?)?.toInt() ?? 100;
    final hydration = (vitals['hydration'] as num?)?.toInt() ?? 100;
    final happiness = (vitals['happiness'] as num?)?.toInt() ?? 100;
    if (energy < 50 || hunger < 30 || hydration < 30 || happiness < 30) {
      return null;
    }
    if (energy < 65) return PetState.sitting;
    return switch (turn % 4) {
      0 => PetState.thinking,
      1 => PetState.walking,
      2 => PetState.sitting,
      _ => null,
    };
  }
}
