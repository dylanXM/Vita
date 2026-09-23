import 'package:flutter/material.dart';

import '../house/pet_house.dart';
import '../pet/pet_expression.dart';
import '../pet/pet_motion_spec.dart';
import '../pet/pet_renderer.dart';
import '../pet/pet_state_machine.dart';
import '../world_clock.dart';
import 'background_layer.dart';
import 'weather_particles.dart';

/// 场景容器：动态背景 + 宠物小屋 + 宠物 + 天气粒子 + 状态特效。
/// 消费 WorldClock 与 PetStateMachine，不感知 AI 来源。
class PetScene extends StatelessWidget {
  const PetScene({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.machine,
    required this.worldClock,
    required this.weather,
    required this.onTap,
    this.speech,
  });

  final String name;
  final String imageUrl;
  final PetStateMachine machine;
  final WorldClock worldClock;
  final Weather weather;
  final VoidCallback onTap;
  final String? speech;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 330,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: const Color(0xFFFFF6E8),
          ),
          child: AnimatedBuilder(
            animation: Listenable.merge([worldClock, machine]),
            builder: (context, _) {
              final dayProgress = worldClock.dayProgress;
              final worldTime = worldClock.worldTime;
              final state = machine.state;
              final night = dayProgress < .2 || dayProgress > .8;
              final doorOpen = state == PetState.sleeping;
              final smokeOn = state == PetState.levelUp;
              return Stack(
                fit: StackFit.expand,
                children: [
                  BackgroundLayer(
                    dayProgress: dayProgress,
                    worldTime: worldTime,
                  ),
                  Align(
                    alignment: const Alignment(-.82, .86),
                    child: SizedBox(
                      width: 150,
                      height: 150,
                      child: PetHouse(
                        dayProgress: dayProgress,
                        worldTime: worldTime,
                        doorAmount: doorOpen ? 1 : 0,
                        lightOn: night,
                        smokeOn: smokeOn,
                      ),
                    ),
                  ),
                  PetRenderer(
                    name: name,
                    imageUrl: imageUrl,
                    machine: machine,
                    worldTime: worldTime,
                  ),
                  Positioned.fill(
                    child: WeatherParticles(
                      weather: weather,
                      worldTime: worldTime,
                    ),
                  ),
                  PetFxLayer(state: state, speech: speech),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
