import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vita/features/chat/experience_environment.dart';
import 'package:vita/features/chat/shared_experience_stage.dart';

void main() {
  test('scene state tolerates legacy or malformed payloads', () {
    expect(sharedSceneSituation({'payload': 'legacy'}), isEmpty);
    expect(
        sharedSceneFocus({
          'payload': {'scene_focus': 'unknown'}
        }),
        'ambient');
    expect(
        sharedSceneActions({
          'payload': {
            'scene_actions': [
              {'label': 5, 'message': 'invalid'}
            ]
          }
        }),
        isEmpty);
    expect(
        sharedSceneSituation({
          'payload': {'scene_situation': '窗边的对话还在继续。'}
        }),
        '窗边的对话还在继续。');
  });

  testWidgets(
      'missing portraits keep a visible person and stable environment in RTL',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Directionality(
                textDirection: TextDirection.rtl,
                child: ExperienceEnvironment(location: 'cafe', name: 'TA')))));
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(tester.getSize(find.byType(ExperienceEnvironment)).height, 300);
    expect(tester.takeException(), isNull);
  });
}
