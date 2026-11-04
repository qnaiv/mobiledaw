// 曲を MIDI ファイル（SMF タイプ1）にする。トラックごとに1本、テンポと拍子は先頭のトラックに。
import 'dart:convert';
import 'dart:typed_data';

import '../model/project.dart';

class _Event {
  _Event(this.tick, this.order, this.bytes);
  final int tick;
  final int order; // 同じ tick ではノートオフを先に
  final List<int> bytes;
}

Uint8List buildMidi(ProjectData p) {
  final tracks = <List<int>>[];

  // 0本目：曲名・テンポ・拍子
  final usPerBeat = (60000000 / p.tempo).round();
  final den = {1: 0, 2: 1, 4: 2, 8: 3, 16: 4}[p.timeSigDenominator] ?? 2;
  tracks.add(_trackBytes([
    _Event(0, 0, _meta(0x03, utf8.encode(p.title))),
    _Event(0, 0, _meta(0x51, [usPerBeat >> 16 & 0xFF, usPerBeat >> 8 & 0xFF, usPerBeat & 0xFF])),
    _Event(0, 0, _meta(0x58, [p.timeSigNumerator, den, 24, 8])),
  ]));

  final tpb = p.ticksPerBar;
  for (var i = 0; i < p.tracks.length; i++) {
    final t = p.tracks[i];
    final ch = i < 9 ? i : i + 1; // 10ch（ドラム）は避ける
    final events = <_Event>[_Event(0, 0, _meta(0x03, utf8.encode(t.name)))];
    for (final pl in p.placementsOn(t.id)) {
      final clip = p.clip(pl.clipId);
      if (clip == null || clip.lengthTicks <= 0) continue;
      final start = pl.startBar * tpb;
      final end = pl.endBar * tpb;
      // 配置がクリップより長ければ繰り返す（再生と同じ）
      for (var rep = start; rep < end; rep += clip.lengthTicks) {
        for (final n in clip.notes) {
          final on = rep + n.tick;
          if (on >= end) continue;
          final off = (on + n.length).clamp(on + 1, end);
          final vel = (n.velocity * 127).round().clamp(1, 127);
          events.add(_Event(on, 1, [0x90 | ch, n.pitch, vel]));
          events.add(_Event(off, 0, [0x80 | ch, n.pitch, 0]));
        }
      }
    }
    tracks.add(_trackBytes(events));
  }

  final out = BytesBuilder();
  out.add(ascii.encode('MThd'));
  out.add(_u32(6));
  out.add([0, 1, tracks.length >> 8, tracks.length & 0xFF, ticksPerBeat >> 8, ticksPerBeat & 0xFF]);
  for (final t in tracks) {
    out.add(ascii.encode('MTrk'));
    out.add(_u32(t.length));
    out.add(t);
  }
  return out.toBytes();
}

List<int> _meta(int type, List<int> data) => [0xFF, type, ..._vlq(data.length), ...data];

List<int> _trackBytes(List<_Event> events) {
  events.sort((a, b) => a.tick != b.tick ? a.tick.compareTo(b.tick) : a.order.compareTo(b.order));
  final out = <int>[];
  var last = 0;
  for (final e in events) {
    out.addAll(_vlq(e.tick - last));
    out.addAll(e.bytes);
    last = e.tick;
  }
  out.addAll([0x00, 0xFF, 0x2F, 0x00]); // トラックの終わり
  return out;
}

List<int> _vlq(int v) {
  final bytes = <int>[v & 0x7F];
  v >>= 7;
  while (v > 0) {
    bytes.insert(0, (v & 0x7F) | 0x80);
    v >>= 7;
  }
  return bytes;
}

List<int> _u32(int v) => [v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF];
