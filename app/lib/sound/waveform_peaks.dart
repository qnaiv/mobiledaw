// サンプラー素材（キット内 WAV）の実波形ピークを読む。
// 取れない場合（未ダウンロード・対応外の形式）は null を返し、
// 呼び出し側は見本波形（pseudoPeaks）にフォールバックする。
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

final _kitIdRe = RegExp(r'^[a-z0-9][a-z0-9-]{0,47}$');
final _peaksCache = <String, List<double>?>{};

/// キットの kit.json から音のファイルを探し、波形ピーク（0〜1、bins 本）を返す
Future<List<double>?> loadKitSoundPeaks({
  required String kitsRootPath,
  required String kitId,
  required String soundName,
  int bins = 160,
}) async {
  if (!_kitIdRe.hasMatch(kitId)) return null;
  try {
    final kitJson = await File('$kitsRootPath/$kitId/kit.json').readAsString();
    final j = jsonDecode(kitJson);
    if (j is! Map<String, Object?>) return null;
    String? file;
    final list = j['sounds'];
    if (list is List<Object?>) {
      for (final s in list) {
        if (s is Map<String, Object?> && s['name'] == soundName && s['file'] is String) {
          file = s['file']! as String;
          break;
        }
      }
    }
    if (file == null || file.isEmpty || file.contains('/') || file.contains('..')) return null;
    final path = '$kitsRootPath/$kitId/$file';
    if (_peaksCache.containsKey(path)) return _peaksCache[path];
    final bytes = await File(path).readAsBytes();
    final peaks = wavPeaks(bytes, bins);
    _peaksCache[path] = peaks;
    return peaks;
  } on Object {
    return null;
  }
}

/// WAV バイト列からピーク列を計算する（PCM 8/16/24/32bit と float32 に対応）。
/// 形が違う・対応外なら null
List<double>? wavPeaks(Uint8List bytes, int bins) {
  if (bytes.length < 44 || bins <= 0) return null;
  final bd = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  var format = 0;
  var channels = 0;
  var bits = 0;
  var dataOff = -1;
  var dataLen = 0;
  var off = 12;
  while (off + 8 <= bytes.length) {
    final id = tag(off);
    final size = bd.getUint32(off + 4, Endian.little);
    final body = off + 8;
    if (body + size > bytes.length && id != 'data') break;
    if (id == 'fmt ' && size >= 16) {
      format = bd.getUint16(body, Endian.little);
      channels = bd.getUint16(body + 2, Endian.little);
      bits = bd.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOff = body;
      dataLen = math.min(size, bytes.length - body);
    }
    off = body + size + (size.isOdd ? 1 : 0);
  }
  if (dataOff < 0 || channels <= 0 || bits <= 0) return null;
  final bytesPerSample = (bits / 8).ceil();
  final frameBytes = bytesPerSample * channels;
  if (frameBytes <= 0) return null;
  final frames = dataLen ~/ frameBytes;
  if (frames <= 0) return null;

  double sampleAt(int frame, int ch) {
    final o = dataOff + frame * frameBytes + ch * bytesPerSample;
    if (format == 3 && bits == 32) return bd.getFloat32(o, Endian.little);
    switch (bits) {
      case 8:
        return (bytes[o] - 128) / 128;
      case 16:
        return bd.getInt16(o, Endian.little) / 32768;
      case 24:
        var v = bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16);
        if (v & 0x800000 != 0) v -= 0x1000000;
        return v / 8388608;
      case 32:
        return bd.getInt32(o, Endian.little) / 2147483648;
      default:
        return 0;
    }
  }

  final peaks = List<double>.filled(bins, 0);
  for (var f = 0; f < frames; f++) {
    final b = (f * bins) ~/ frames;
    for (var ch = 0; ch < channels; ch++) {
      final a = sampleAt(f, ch).abs();
      if (a > peaks[b]) peaks[b] = a;
    }
  }
  var peak = 0.0;
  for (final p in peaks) {
    peak = math.max(peak, p);
  }
  if (peak <= 0) return List<double>.filled(bins, 0);
  return [for (final p in peaks) math.min(1.0, p / peak)];
}
