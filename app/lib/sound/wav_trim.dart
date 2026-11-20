// WAV の時間範囲切り出し（Phase 2.6 の部分バウンス用）。
// 書き出し WAV（24bit PCM ステレオ 48kHz）を [startSec, endSec) で切り、
// 同じ形式の WAV バイト列を返す。PCM 8/16/24/32bit と float32 に対応し、
// fmt チャンクはそのまま引き継ぐ（data チャンクだけ差し替える）。
// 対応できない形・範囲が空なら null。
import 'dart:math' as math;
import 'dart:typed_data';

/// WAV バイト列から [startSec, endSec) の区間を切り出す。
/// endSec が素材の長さを超える場合は末尾までに丸める。
Uint8List? trimWavBytes(Uint8List bytes, double startSec, double endSec) {
  if (bytes.length < 44 || startSec < 0 || endSec <= startSec) return null;
  final bd = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;

  var channels = 0;
  var sampleRate = 0;
  var bits = 0;
  var fmtOff = -1;
  var fmtLen = 0;
  var dataOff = -1;
  var dataLen = 0;
  var off = 12;
  while (off + 8 <= bytes.length) {
    final id = tag(off);
    final size = bd.getUint32(off + 4, Endian.little);
    final body = off + 8;
    if (id == 'fmt ' && size >= 16 && body + size <= bytes.length) {
      channels = bd.getUint16(body + 2, Endian.little);
      sampleRate = bd.getUint32(body + 4, Endian.little);
      bits = bd.getUint16(body + 14, Endian.little);
      fmtOff = body;
      fmtLen = size;
    } else if (id == 'data') {
      dataOff = body;
      dataLen = math.min(size, bytes.length - body);
      break; // data の後ろは読まない（書き出し WAV は data が最後）
    }
    if (body + size > bytes.length) break;
    off = body + size + (size.isOdd ? 1 : 0);
  }
  if (dataOff < 0 || fmtOff < 0 || channels <= 0 || sampleRate <= 0 || bits <= 0) return null;
  final frameBytes = (bits / 8).ceil() * channels;
  if (frameBytes <= 0) return null;
  final totalFrames = dataLen ~/ frameBytes;
  if (totalFrames <= 0) return null;

  var startFrame = (startSec * sampleRate).round();
  var endFrame = (endSec * sampleRate).round();
  startFrame = startFrame.clamp(0, totalFrames);
  endFrame = endFrame.clamp(0, totalFrames);
  if (endFrame <= startFrame) return null;

  final outDataLen = (endFrame - startFrame) * frameBytes;
  final out = BytesBuilder();
  final header = ByteData(8);
  void putTag(String s) => out.add(s.codeUnits);
  // RIFF ヘッダー
  putTag('RIFF');
  header.setUint32(0, 4 + (8 + fmtLen + (fmtLen.isOdd ? 1 : 0)) + 8 + outDataLen + (outDataLen.isOdd ? 1 : 0), Endian.little);
  out.add(header.buffer.asUint8List(0, 4));
  putTag('WAVE');
  // fmt チャンク（元のものをそのまま）
  putTag('fmt ');
  header.setUint32(0, fmtLen, Endian.little);
  out.add(header.buffer.asUint8List(0, 4));
  out.add(Uint8List.sublistView(bytes, fmtOff, fmtOff + fmtLen));
  if (fmtLen.isOdd) out.addByte(0);
  // data チャンク（切り出した区間）
  putTag('data');
  header.setUint32(0, outDataLen, Endian.little);
  out.add(header.buffer.asUint8List(0, 4));
  final srcStart = dataOff + startFrame * frameBytes;
  out.add(Uint8List.sublistView(bytes, srcStart, srcStart + outDataLen));
  if (outDataLen.isOdd) out.addByte(0);
  return out.toBytes();
}
