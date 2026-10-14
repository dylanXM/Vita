import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vita/features/encounters/encounter_dock.dart';

void main() {
  testWidgets('dock keeps tabs compact and raises center action with border', (tester) async {
    var selected = -1;
    var creates = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: EncounterDock(index: 0,
            onTab: (index) => selected = index,
            onCreate: () async { creates++; }),
        ),
      ),
    ));
    await tester.pump();
    final tab = find.ancestor(of: find.byIcon(Icons.explore_outlined), matching: find.byType(InkWell)).first;
    expect(tester.getSize(tab).height, 44);
    final plus = tester.getCenter(find.byIcon(Icons.add_rounded));
    final tabCenter = tester.getCenter(find.byIcon(Icons.explore_outlined));
    expect(plus.dy, lessThan(tabCenter.dy));
    final labelCenter = tester.getCenter(find.text('encounter.explore'));
    expect(labelCenter.dy, closeTo(tabCenter.dy, 1));
    expect(labelCenter.dx, greaterThan(tabCenter.dx));
    expect(find.descendant(of: find.byType(EncounterDock), matching: find.byType(CustomPaint)), findsWidgets);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    expect(selected, 1);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(creates, 1);
    expect(tester.takeException(), isNull);
  });
  test('dock outline follows both sides of the center circle', () {
    const size = Size(350, 84);
    final outline = encounterDockOutline(size);
    expect(outline.contains(const Offset(175, 81)), isTrue);
    expect(outline.contains(const Offset(175, 83)), isFalse);
    expect(outline.contains(const Offset(175, 3)), isTrue);
    expect(outline.contains(const Offset(175, 1)), isFalse);
    expect(outline.contains(const Offset(115, 75)), isFalse);
  });
}
