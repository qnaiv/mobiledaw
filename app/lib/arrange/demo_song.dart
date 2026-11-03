// メニュー「デモ曲を入れる」で入る曲。
// ・シンプル：C minor、2小節（Cm | A♭ B♭）を2回。再生と並びの確かめ用
// ・フューチャーベース：150 BPM、溜めの4小節 → 刻むドロップの4小節。コード系の機能（進行・リズム）で組んである
import '../engine/mdaw_ffi.dart';
import '../model/project.dart';
import '../music/progressions.dart';
import '../music/scale.dart';
import '../music/voicing.dart';

enum DemoSong { simple, futureBass }

String demoLabel(DemoSong d) => switch (d) {
      DemoSong.simple => 'シンプル（4トラック・4小節）',
      DemoSong.futureBass => 'フューチャーベース（5トラック・8小節）',
    };

void buildDemo(MdawEngine e, DemoSong demo) {
  switch (demo) {
    case DemoSong.simple:
      buildDemoSong(e);
    case DemoSong.futureBass:
      buildFutureBassDemo(e);
  }
}

const int _beat = ticksPerBeat;

/// (拍, 長さ（拍）, 音程)
typedef _N = (double, double, int);

void buildDemoSong(MdawEngine e) {
  e.editGroup(() {
    e.setTempo(100);
    final arp = e.project.tracks.first.id;
    final bass = e.addTrack('Bass', 0xFF5AA9F2);
    final chord = e.addTrack('Chord', 0xFFC8F25A);
    final lead = e.addTrack('Lead', 0xFFE879C6);

    _sound(e, arp, cutoff: 3200, decay: 0.15, sustain: 0.15, release: 0.15, detune: 6);
    _sound(e, bass, cutoff: 650, decay: 0.3, sustain: 0.5, release: 0.08, detune: 3);
    _sound(e, chord, cutoff: 2200, attack: 0.03, decay: 0.6, sustain: 0.6, release: 0.5, detune: 12);
    _sound(e, lead, cutoff: 5200, decay: 0.3, sustain: 0.7, release: 0.2, detune: 9);

    // 2小節目は前半 A♭、後半 B♭
    final arpNotes = <_N>[
      for (var i = 0; i < 8; i++) (i * 0.5, 0.5, const [60, 63, 67, 72, 67, 63, 67, 72][i]),
      for (var i = 0; i < 4; i++) (4 + i * 0.5, 0.5, const [56, 60, 63, 68][i]),
      for (var i = 0; i < 4; i++) (6 + i * 0.5, 0.5, const [58, 62, 65, 70][i]),
    ];
    const bassNotes = <_N>[
      (0.0, 1.5, 36), (1.5, 0.5, 36), (2.0, 1.0, 36), (3.0, 1.0, 43),
      (4.0, 1.5, 44), (5.5, 0.5, 44), (6.0, 1.0, 46), (7.0, 1.0, 46),
    ];
    const chordNotes = <_N>[
      (0.0, 3.9, 60), (0.0, 3.9, 63), (0.0, 3.9, 67),
      (4.0, 1.9, 56), (4.0, 1.9, 60), (4.0, 1.9, 63),
      (6.0, 1.9, 58), (6.0, 1.9, 62), (6.0, 1.9, 65),
    ];
    const leadNotes = <_N>[
      (0.0, 1.0, 72), (1.0, 0.5, 75), (1.5, 0.5, 74), (2.0, 1.0, 72), (3.0, 1.0, 70),
      (4.0, 1.5, 68), (5.5, 0.5, 67), (6.0, 1.0, 70), (7.0, 1.0, 67),
    ];

    for (final (track, notes) in [(arp, arpNotes), (bass, bassNotes), (chord, chordNotes), (lead, leadNotes)]) {
      final (clip, _) = e.createClip(track, 0, lengthBars: 2);
      for (final (start, len, pitch) in notes) {
        e.addNote(clip,
            tick: (start * _beat).round(), length: (len * _beat).round() - 10, pitch: pitch, velocity: 0.8);
      }
      e.placeClip(clip, 2); // 3〜4小節目にもう一度
    }
  });
}

void _sound(MdawEngine e, int track,
    {required double cutoff,
    double attack = 0.005,
    required double decay,
    required double sustain,
    required double release,
    required double detune}) {
  e.setTrackParam(track, MdawParam.cutoffHz, cutoff);
  e.setTrackParam(track, MdawParam.attackS, attack);
  e.setTrackParam(track, MdawParam.decayS, decay);
  e.setTrackParam(track, MdawParam.sustain, sustain);
  e.setTrackParam(track, MdawParam.releaseS, release);
  e.setTrackParam(track, MdawParam.detuneCents, detune);
}

// ---- フューチャーベース ----------------------------------------------------------

void buildFutureBassDemo(MdawEngine e) {
  e.editGroup(() {
    e.setTempo(150);
    final p = e.project;
    final tpb = p.ticksPerBar; // 3840
    const scale = Scale(0, Scale.minorIntervals); // C minor

    final chordsTrack = p.tracks.first.id;
    e.renameTrack(chordsTrack, 'Chords');
    final sub = e.addTrack('Sub', 0xFF5AA9F2);
    final lead = e.addTrack('Lead', 0xFFE879C6);
    final pluck = e.addTrack('Pluck', 0xFF9A7CF2);
    final kick = e.addTrack('Kick', 0xFFF28C38);

    // 厚く広がるのこぎり波（大きくデチューン）
    _sound(e, chordsTrack, cutoff: 6500, attack: 0.01, decay: 0.5, sustain: 0.75, release: 0.3, detune: 32);
    e.setTrackParam(chordsTrack, MdawParam.masterGain, 0.5);
    _sound(e, sub, cutoff: 380, attack: 0.004, decay: 0.3, sustain: 0.9, release: 0.06, detune: 0);
    _sound(e, lead, cutoff: 4200, attack: 0.003, decay: 0.16, sustain: 0.25, release: 0.12, detune: 10);
    _sound(e, pluck, cutoff: 3000, attack: 0.002, decay: 0.12, sustain: 0.0, release: 0.1, detune: 14);
    e.setTrackParam(pluck, MdawParam.masterGain, 0.45);
    _sound(e, kick, cutoff: 160, attack: 0.001, decay: 0.14, sustain: 0.0, release: 0.05, detune: 0);
    e.setTrackParam(kick, MdawParam.resonance, 4);
    e.setTrackParam(kick, MdawParam.masterGain, 0.9);

    // A♭M7 → B♭ → Gm7 → Cm9（切ない王道に色をつけたもの）。なめらかにつながる高さで
    final preset = minorPresets.firstWhere((x) => x.name == 'フューチャーベース');
    final chords = [for (final r in preset.romans) chordFromRoman(r, scale)!];
    final voiced = voiceProgression(chords, center: 62);

    void fill(int clip, List<NoteSpec> notes) {
      for (final n in notes) {
        e.addNote(clip, tick: n.tick, length: n.length, pitch: n.pitch, velocity: n.velocity);
      }
    }

    // Chords：溜め（1〜4小節）は伸ばす、ドロップ（5〜8小節）はシンコペで刻む
    final (build, _) = e.createClip(chordsTrack, 0, lengthBars: 4);
    final (drop, _) = e.createClip(chordsTrack, 4, lengthBars: 4);
    for (var i = 0; i < 4; i++) {
      fill(build, rhythmize(voiced[i], start: i * tpb, length: tpb - 30, rhythm: ChordRhythm.block, velocity: 0.7));
      fill(drop, rhythmize(voiced[i], start: i * tpb, length: tpb, rhythm: ChordRhythm.syncopated, velocity: 0.95));
    }

    // Pluck：溜めの間、コードを1オクターブ上で16分のアルペジオ
    final (arp, _) = e.createClip(pluck, 0, lengthBars: 4);
    for (var i = 0; i < 4; i++) {
      fill(arp, rhythmize([for (final x in voiced[i]) x + 12], start: i * tpb, length: tpb, rhythm: ChordRhythm.arpUpDown, velocity: 0.6));
    }

    // Sub：ドロップで根音をコードと同じ所で鳴らす
    final (subClip, _) = e.createClip(sub, 4, lengthBars: 4);
    const roots = [32, 34, 31, 36]; // A♭1 B♭1 G1 C2
    for (var i = 0; i < 4; i++) {
      fill(subClip, rhythmize([roots[i], roots[i] + 7, roots[i] + 12], start: i * tpb, length: tpb, rhythm: ChordRhythm.syncopated)
          .where((n) => n.pitch == roots[i])
          .toList());
    }

    // Kick：ドロップの半分の速さのノリ（1拍目と3拍目の裏寄り）
    final (kickClip, _) = e.createClip(kick, 4, lengthBars: 1);
    for (final t in [0, 1680, 2880]) {
      e.addNote(kickClip, tick: t, length: 360, pitch: 24, velocity: 1.0);
    }
    for (final bar in [5, 6, 7]) {
      e.placeClip(kickClip, bar);
    }

    // Lead：4小節のメロディを溜めとドロップの両方で
    final (melody, _) = e.createClip(lead, 0, lengthBars: 4);
    const tune = <_N>[
      (0.0, 0.75, 79), (0.75, 0.75, 75), (1.5, 0.5, 72), (2.0, 1.0, 75), (3.0, 1.0, 77),
      (4.0, 0.75, 77), (4.75, 0.75, 74), (5.5, 0.5, 70), (6.0, 1.0, 74), (7.0, 1.0, 75),
      (8.0, 0.75, 74), (8.75, 0.75, 70), (9.5, 0.5, 67), (10.0, 1.0, 70), (11.0, 1.0, 74),
      (12.0, 1.5, 75), (13.5, 0.5, 74), (14.0, 2.0, 72),
    ];
    for (final (start, len, pitch) in tune) {
      e.addNote(melody, tick: (start * _beat).round(), length: (len * _beat).round() - 20, pitch: pitch, velocity: 0.85);
    }
    e.placeClip(melody, 4);
  });
}
