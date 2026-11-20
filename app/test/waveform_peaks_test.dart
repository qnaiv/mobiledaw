import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/sound/waveform_peaks.dart';

// サンプラー素材の実波形ローダー（WAV 解析）のテスト。
Uint8List _wav16({required int frames, int channels = 1}) {
  final data = ByteData(frames * channels * 2);
  for (var f = 0; f < frames; f++) {
    final v = (math.sin(f / frames * math.pi * 6) * 30000).round();
    for (var ch = 0; ch < channels; ch++) {
      data.setInt16((f * channels + ch) * 2, v, Endian.little);
    }
  }
  final dataBytes = data.buffer.asUint8List();
  final out = BytesBuilder();
  void tag(String s) => out.add(ascii.encode(s));
  void u32(int v) => out.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) => out.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  tag('RIFF');
  u32(36 + dataBytes.length);
  tag('WAVE');
  tag('fmt ');
  u32(16);
  u16(1); // PCM
  u16(channels);
  u32(48000);
  u32(48000 * channels * 2);
  u16(channels * 2);
  u16(16);
  tag('data');
  u32(dataBytes.length);
  out.add(dataBytes);
  return out.takeBytes();
}

void main() {
  test('wavPeaks が 16bit PCM を読む', () {
    final peaks = wavPeaks(_wav16(frames: 4800), 16);
    expect(peaks, isNotNull);
    expect(peaks!.length, 16);
    expect(peaks.reduce(math.max), closeTo(1.0, 0.001)); // 最大ピークで正規化される
    expect(peaks.any((p) => p > 0.1), isTrue);
  });

  test('wavPeaks はステレオでも読める', () {
    final peaks = wavPeaks(_wav16(frames: 2400, channels: 2), 8);
    expect(peaks, isNotNull);
    expect(peaks!.length, 8);
  });

  test('wavPeaks は WAV でないものを null にする', () {
    expect(wavPeaks(Uint8List.fromList([1, 2, 3, 4, 5]), 8), isNull);
    expect(wavPeaks(Uint8List(100), 8), isNull);
  });

  test('loadKitSoundPeaks がキットの音を読む', () async {
    final dir = await Directory.systemTemp.createTemp('mdaw_peaks');
    addTearDown(() => dir.delete(recursive: true));
    final kitDir = Directory('${dir.path}/test-kit')..createSync();
    File('${kitDir.path}/kit.json').writeAsStringSync(jsonEncode({
      'name': 'Test',
      'sounds': [
        {'name': 'Phrase', 'file': 'phrase.wav', 'note': 60},
      ],
    }));
    File('${kitDir.path}/phrase.wav').writeAsBytesSync(_wav16(frames: 4800));
    final peaks = await loadKitSoundPeaks(kitsRootPath: dir.path, kitId: 'test-kit', soundName: 'Phrase');
    expect(peaks, isNotNull);
    expect(peaks!.length, 160);
    expect(peaks.any((p) => p > 0.5), isTrue);

    final missing = await loadKitSoundPeaks(kitsRootPath: dir.path, kitId: 'test-kit', soundName: '無い音');
    expect(missing, isNull);
    final badId = await loadKitSoundPeaks(kitsRootPath: dir.path, kitId: '../etc', soundName: 'Phrase');
    expect(badId, isNull);
  });
}
