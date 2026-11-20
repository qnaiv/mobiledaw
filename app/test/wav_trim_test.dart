import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/sound/wav_trim.dart';

// Phase 2.6 の部分バウンス: WAV の時間範囲切り出し（純関数）の検証。
// ランプ波形（サンプル値 = フレーム番号が分かる形）を切り、
// フレーム数と切り出し位置の両方を見る。

/// フレーム i の左サンプルが i そのものになる小さな WAV を作る
Uint8List _rampWav({required int bits, required int channels, required int frames, int sampleRate = 48000}) {
  final bytesPerSample = bits ~/ 8;
  final frameBytes = bytesPerSample * channels;
  final dataLen = frameBytes * frames;
  final out = BytesBuilder();
  final u32 = ByteData(4);
  void tag(String s) => out.add(s.codeUnits);
  void put32(int v) {
    u32.setUint32(0, v, Endian.little);
    out.add(u32.buffer.asUint8List());
  }

  tag('RIFF');
  put32(36 + dataLen);
  tag('WAVE');
  tag('fmt ');
  put32(16);
  final fmt = ByteData(16);
  fmt.setUint16(0, 1, Endian.little); // PCM
  fmt.setUint16(2, channels, Endian.little);
  fmt.setUint32(4, sampleRate, Endian.little);
  fmt.setUint32(8, sampleRate * frameBytes, Endian.little);
  fmt.setUint16(12, frameBytes, Endian.little);
  fmt.setUint16(14, bits, Endian.little);
  out.add(fmt.buffer.asUint8List());
  tag('data');
  put32(dataLen);
  final body = ByteData(dataLen);
  for (var i = 0; i < frames; i++) {
    for (var ch = 0; ch < channels; ch++) {
      final off = i * frameBytes + ch * bytesPerSample;
      if (bits == 16) {
        body.setInt16(off, i, Endian.little);
      } else if (bits == 24) {
        final v = i;
        body.setUint8(off, v & 0xff);
        body.setUint8(off + 1, (v >> 8) & 0xff);
        body.setUint8(off + 2, (v >> 16) & 0xff);
      }
    }
  }
  out.add(body.buffer.asUint8List());
  return out.toBytes();
}

({int dataOff, int dataLen, int riffSize}) _layout(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
  var off = 12;
  var dataOff = -1;
  var dataLen = 0;
  while (off + 8 <= bytes.length) {
    final size = bd.getUint32(off + 4, Endian.little);
    if (tag(off) == 'data') {
      dataOff = off + 8;
      dataLen = size;
      break;
    }
    off += 8 + size + (size.isOdd ? 1 : 0);
  }
  return (dataOff: dataOff, dataLen: dataLen, riffSize: bd.getUint32(4, Endian.little));
}

int _frameValue24(Uint8List bytes, int dataOff, int frameBytes, int frame) {
  final o = dataOff + frame * frameBytes;
  return bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16);
}

void main() {
  test('24bit ステレオを区間どおりに切る', () {
    // 48000 フレーム = 1 秒。0.25〜0.75 秒 → 24000 フレーム
    final wav = _rampWav(bits: 24, channels: 2, frames: 48000);
    final trimmed = trimWavBytes(wav, 0.25, 0.75);
    expect(trimmed, isNotNull);
    final layout = _layout(trimmed!);
    expect(layout.dataLen, 24000 * 6); // 24bit × 2ch = 6 バイト/フレーム
    expect(layout.riffSize, trimmed.length - 8);
    // 先頭フレームは元の 12000 番目のフレーム
    expect(_frameValue24(trimmed, layout.dataOff, 6, 0), 12000);
    expect(_frameValue24(trimmed, layout.dataOff, 6, 23999), 35999);
  });

  test('16bit モノも切れる。末尾は素材長で丸める', () {
    final wav = _rampWav(bits: 16, channels: 1, frames: 24000); // 0.5 秒
    final trimmed = trimWavBytes(wav, 0.1, 99.0);
    expect(trimmed, isNotNull);
    final layout = _layout(trimmed!);
    expect(layout.dataLen, (24000 - 4800) * 2);
  });

  test('不正な入力は null', () {
    expect(trimWavBytes(Uint8List(10), 0, 1), isNull);
    final wav = _rampWav(bits: 24, channels: 2, frames: 4800);
    expect(trimWavBytes(wav, 0.2, 0.2), isNull); // 空の範囲
    expect(trimWavBytes(wav, -0.1, 0.5), isNull); // 負の開始
    expect(trimWavBytes(wav, 0.5, 0.9), isNull); // 素材の外（0.1 秒しかない）
  });
}
