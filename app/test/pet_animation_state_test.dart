import 'package:flutter_test/flutter_test.dart';
import 'package:vita/features/ai_pets/animation/pet/mesh_bone_pet.dart';
import 'package:vita/features/ai_pets/animation/pet/pet_motion_spec.dart';
import 'package:vita/features/ai_pets/animation/pet/pet_state_machine.dart';

void main() {
  test('torso and tail deform their own mesh regions', () {
    final neutralBody = offsetAt(const MeshPose(), .5, .5, 0);
    final leaningBody = offsetAt(const MeshPose(bodyLean: .1), .5, .5, 0);
    expect(leaningBody.dx, isNot(equals(neutralBody.dx)));

    final neutralTail = offsetAt(const MeshPose(), .875, .625, .25);
    final movingTail = offsetAt(const MeshPose(tailSwing: .1), .875, .625, .25);
    expect(movingTail.dx, isNot(equals(neutralTail.dx)));
  });

  testWidgets('an interrupted transition keeps the current blended pose',
      (tester) async {
    final machine = PetStateMachine(vsync: const TestVSync());
    addTearDown(machine.dispose);

    machine.transition(PetState.sitting);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final sittingWeight = machine.weightFor(PetState.sitting);
    expect(sittingWeight, greaterThan(0));
    expect(sittingWeight, lessThan(1));

    machine.transition(PetState.walking);
    expect(machine.weightFor(PetState.sitting), closeTo(sittingWeight, .001));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(machine.weightFor(PetState.walking), greaterThan(0));
    expect(machine.weightFor(PetState.sitting), lessThan(sittingWeight));
  });
}
