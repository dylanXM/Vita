import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vita/features/ai_pets/animation/pet/pet_atlas_frames.dart';
import 'package:vita/features/ai_pets/animation/pet/companion_pet_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('an ear crossing a cell boundary stays with its own pose', () {
    final mask = Uint8List(40 * 40 * 4);
    final color = Uint8List(40 * 40 * 4)..fillRange(0, 40 * 40 * 4, 255);
    void rectangle(int left, int top, int right, int bottom) {
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) mask[(y * 40 + x) * 4] = 255;
      }
    }
    rectangle(5, 4, 14, 17);
    rectangle(25, 4, 34, 17);
    rectangle(5, 24, 14, 37);
    rectangle(25, 24, 34, 37);
    rectangle(8, 19, 11, 25); // Lower pose's ear crosses the row boundary.
    final frames = buildPetAtlasFrames(color, mask, 40, 40, columns: 2, rows: 2);
    expect(frames.bounds[2].top, 19);
    expect(frames.bounds[0].bottom, 17);
    final retained = List.generate(frames.rgba.length ~/ 4,
      (i) => frames.rgba[i * 4 + 3]).where((a) => a > 0).length;
    expect(retained, mask.where((value) => value > 0).length);
  });
  testWidgets('room renderer loads and switches direction without errors', (tester) async {
    Future<void> show(bool left, double seconds) async {
      await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(
        width: 210, height: 210, child: CompanionPetArt(name: 'Momo',
          imageUrl: 'asset://assets/ai_pets/dog_shiba.png', seconds: seconds,
          facingLeft: left)))));
    }
    await show(true, 0);
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(seconds: 1)); });
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
    await show(false, 2);
    await show(false, 2.2);
    await show(false, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('all room poses retain complete silhouettes without neighboring frames', () async {
    for (final breed in ['cat_orange', 'cat_tuxedo', 'cat_ragdoll',
      'dog_corgi', 'dog_shiba', 'dog_retriever']) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xff302a25), ui.BlendMode.src);
      var index = 0;
      for (final turn in [false, true]) {
        final base = 'assets/ai_pets/motion_v3/${breed}_room';
        Future<ui.Image> load(String path) async {
          final data = await rootBundle.load(path);
          final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
          final image = (await codec.getNextFrame()).image;
          codec.dispose();
          return image;
        }
        final color = await load('$base${turn ? '_turn' : '_motion'}.png');
        final mask = await load('$base${turn ? '_turn_mask' : '_mask'}.png');
        final colorBytes = (await color.toByteData())!.buffer.asUint8List();
        final maskBytes = (await mask.toByteData())!.buffer.asUint8List();
        final columns = turn ? 3 : 4, rows = turn ? 2 : 6;
        final frames = buildPetAtlasFrames(colorBytes, maskBytes,
          color.width, color.height, columns: columns, rows: rows);
        final decoded = Completer<ui.Image>();
        ui.decodeImageFromPixels(frames.rgba, frames.width, frames.height, ui.PixelFormat.rgba8888, decoded.complete);
        final packed = await decoded.future;
        final pw = frames.width ~/ columns, ph = frames.height ~/ rows;
        for (var frame = 0; frame < columns * rows; frame++) {
          final b = frames.bounds[frame];
          final originalX = frame % columns * frames.cellWidth;
          final originalY = frame ~/ columns * frames.cellHeight;
          expect(b.left - originalX + frames.padding, greaterThanOrEqualTo(2));
          expect(b.top - originalY + frames.padding, greaterThanOrEqualTo(2));
          expect(b.right - originalX + frames.padding, lessThanOrEqualTo(pw - 2));
          expect(b.bottom - originalY + frames.padding, lessThanOrEqualTo(ph - 2));
          final extent = 150 * frames.frameScale * frames.fitScale;
          final x = index % 6 * 160.0, y = index ~/ 6 * 160.0;
          canvas.drawImageRect(packed,
            ui.Rect.fromLTWH(frame % columns * pw.toDouble(), frame ~/ columns * ph.toDouble(), pw.toDouble(), ph.toDouble()),
            ui.Rect.fromLTWH(x + (160 - extent) / 2, y + 150 - frames.baselines[frame] * extent, extent, extent), ui.Paint());
          index++;
        }
        packed.dispose(); color.dispose(); mask.dispose();
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(960, 800);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/private/tmp/vita_$breed.png').writeAsBytes(png!.buffer.asUint8List());
      image.dispose(); picture.dispose();
    }
  });
}
