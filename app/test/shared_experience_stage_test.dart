import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vita/features/chat/experience_environment.dart';
import 'package:vita/features/chat/shared_experience_stage.dart';

void main() {
  test('scene timeline preserves temporal order and replaces repeated rows',
      () {
    final messages = chronologicalSceneMessages([
      {
        'id': 'reply',
        'sender_type': 'assistant',
        'content': 'TA reply',
        'created_at': '2026-10-13T08:00:02Z'
      },
      {
        'id': 'user',
        'sender_type': 'user',
        'content': 'Your words',
        'created_at': '2026-10-13T08:00:01Z'
      },
      {
        'id': 'reply',
        'sender_type': 'assistant',
        'content': 'Updated TA reply',
        'created_at': '2026-10-13T08:00:02Z'
      },
    ]);
    expect(messages.map((m) => m['id']).toList(), ['user', 'reply']);
    expect(messages.last['content'], 'Updated TA reply');
  });

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
