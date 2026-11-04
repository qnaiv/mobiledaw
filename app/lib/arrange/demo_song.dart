// メニュー「デモ曲を入れる」で入る曲。
// ・シンプル：C minor、2小節（Cm | A♭ B♭）を2回。再生と並びの確かめ用（ここで組み立てる）
// ・フューチャーベース：150 BPM、溜め8小節 → ドロップ8小節、8トラック。
//   同梱のプロジェクトファイル（assets/demos/future_bass.json）を読む。
//   ファイルは tools/demos/future_bass.py で作り、build/mdaw_render で wav にして音を確かめる
import '../engine/mdaw_ffi.dart';
import '../model/project.dart';

enum DemoSong { simple, futureBass }

String demoLabel(DemoSong d) => switch (d) {
      DemoSong.simple => 'シンプル（4トラック・4小節）',
      DemoSong.futureBass => 'フューチャーベース（8トラック・16小節）',
    };

/// 同梱のプロジェクトファイルで入る曲はそのパス。null ならコードで組み立てる（[buildDemoSong]）
String? demoAsset(DemoSong d) => switch (d) {
      DemoSong.simple => null,
      DemoSong.futureBass => 'assets/demos/future_bass.json',
    };

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
