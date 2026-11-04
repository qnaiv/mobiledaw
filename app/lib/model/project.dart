// プロジェクトの中身（読み取り専用）。コアの mdaw_project_json が返す JSON（project.json と同じ形）を読む。
// 編集は MdawEngine の操作を呼び、変わったら読み直す（ProjectData は毎回作り直す）。
import 'dart:convert';

/// 1拍あたりの tick（コアの kPpq と揃える）
const int ticksPerBeat = 960;

/// ID は 64bit。JSON では16桁の16進文字列、Dart では int（上位ビットが立つと負の数になる）で持つ。
int parseId(Object? value) {
  if (value is! String || value.length != 16) return 0;
  final big = BigInt.tryParse(value, radix: 16);
  return big == null ? 0 : big.toSigned(64).toInt();
}

String formatId(int id) => BigInt.from(id).toUnsigned(64).toRadixString(16).padLeft(16, '0');

class NoteData {
  const NoteData({
    required this.id,
    required this.tick,
    required this.length,
    required this.pitch,
    required this.velocity,
  });

  final int id;
  final int tick; // クリップ先頭から
  final int length;
  final int pitch; // MIDI 0〜127
  final double velocity;

  int get endTick => tick + length;

  factory NoteData.fromJson(Map<String, Object?> j) => NoteData(
        id: parseId(j['id']),
        tick: _int(j['tick']),
        length: _int(j['length']),
        pitch: _int(j['pitch']),
        velocity: _double(j['velocity'], 0.8),
      );
}

class ClipData {
  const ClipData({required this.id, required this.trackId, required this.lengthTicks, required this.notes});

  final int id;
  final int trackId;
  final int lengthTicks;
  final List<NoteData> notes; // tick → pitch の順

  factory ClipData.fromJson(Map<String, Object?> j) => ClipData(
        id: parseId(j['id']),
        trackId: parseId(j['trackId']),
        lengthTicks: _int(j['lengthTicks']),
        notes: _list(j['notes']).map(NoteData.fromJson).toList(growable: false),
      );
}

class PlacementData {
  const PlacementData({
    required this.id,
    required this.clipId,
    required this.trackId,
    required this.startBar,
    required this.lengthBars,
  });

  final int id;
  final int clipId;
  final int trackId;
  final int startBar; // 0始まり
  final int lengthBars;

  int get endBar => startBar + lengthBars;

  factory PlacementData.fromJson(Map<String, Object?> j) => PlacementData(
        id: parseId(j['id']),
        clipId: parseId(j['clipId']),
        trackId: parseId(j['trackId']),
        startBar: _int(j['startBar']),
        lengthBars: _int(j['lengthBars'], 1),
      );
}

class MixerData {
  const MixerData({this.gain = 0.8, this.pan = 0, this.mute = false, this.solo = false});

  final double gain;
  final double pan;
  final bool mute;
  final bool solo;

  factory MixerData.fromJson(Map<String, Object?> j) => MixerData(
        gain: _double(j['gain'], 0.8),
        pan: _double(j['pan'], 0),
        mute: j['mute'] == true,
        solo: j['solo'] == true,
      );
}

class TrackData {
  const TrackData({
    required this.id,
    required this.name,
    required this.color,
    required this.synth,
    this.fx = const {},
    required this.mixer,
  });

  final int id;
  final String name;
  final int color; // ARGB
  final Map<String, double> synth; // cutoffHz, resonance, attackS など
  final Map<String, double> fx; // reverb, ott, sidechain など
  final MixerData mixer;

  factory TrackData.fromJson(Map<String, Object?> j) {
    final instrument = _map(j['instrument']);
    final params = _map(instrument['params']);
    return TrackData(
      id: parseId(j['id']),
      name: j['name'] is String ? j['name']! as String : '',
      color: int.tryParse(j['color'] is String ? j['color']! as String : '', radix: 16) ?? 0xFFC8F25A,
      synth: {
        for (final e in params.entries)
          if (e.value is num) e.key: (e.value! as num).toDouble(),
      },
      fx: {
        for (final e in _map(j['fx']).entries)
          if (e.value is num) e.key: (e.value! as num).toDouble(),
      },
      mixer: MixerData.fromJson(_map(j['mixer'])),
    );
  }
}

class ProjectData {
  const ProjectData({
    this.title = '無題の曲',
    required this.tempo,
    required this.timeSigNumerator,
    required this.timeSigDenominator,
    required this.keyRoot,
    required this.scale,
    required this.tracks,
    required this.clips,
    required this.placements,
  });

  final String title;
  final double tempo;
  final int timeSigNumerator;
  final int timeSigDenominator;
  final int keyRoot; // 0 = C
  final String scale;
  final List<TrackData> tracks;
  final List<ClipData> clips;
  final List<PlacementData> placements;

  int get ticksPerBar => ticksPerBeat * 4 * timeSigNumerator ~/ timeSigDenominator;

  /// 曲の長さ（小節数）。最後の配置の終わり
  int get lengthBars => placements.fold(0, (end, p) => p.endBar > end ? p.endBar : end);

  TrackData? track(int id) => _find(tracks, (t) => t.id == id);
  ClipData? clip(int id) => _find(clips, (c) => c.id == id);
  Iterable<PlacementData> placementsOn(int trackId) => placements.where((p) => p.trackId == trackId);

  /// そのトラックの、その小節にかかっている配置
  PlacementData? placementAt(int trackId, int bar) =>
      _find(placements, (p) => p.trackId == trackId && p.startBar <= bar && bar < p.endBar);

  factory ProjectData.fromJson(Map<String, Object?> j) {
    final sig = j['timeSig'] is List ? j['timeSig']! as List<Object?> : const <Object?>[4, 4];
    final key = _map(j['key']);
    return ProjectData(
      title: j['title'] is String && (j['title']! as String).trim().isNotEmpty ? j['title']! as String : '無題の曲',
      tempo: _double(j['tempo'], 120),
      timeSigNumerator: sig.isNotEmpty ? _int(sig[0], 4) : 4,
      timeSigDenominator: sig.length > 1 ? _int(sig[1], 4) : 4,
      keyRoot: _int(key['root']),
      scale: key['scale'] is String ? key['scale']! as String : 'minor',
      tracks: _list(j['tracks']).map(TrackData.fromJson).toList(growable: false),
      clips: _list(j['clips']).map(ClipData.fromJson).toList(growable: false),
      placements: _list(j['placements']).map(PlacementData.fromJson).toList(growable: false),
    );
  }

  static ProjectData parse(String json) => ProjectData.fromJson(_map(jsonDecode(json)));
}

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
double _double(Object? v, double fallback) => v is num ? v.toDouble() : fallback;
Map<String, Object?> _map(Object? v) => v is Map<String, Object?> ? v : const <String, Object?>{};
Iterable<Map<String, Object?>> _list(Object? v) =>
    v is List<Object?> ? v.whereType<Map<String, Object?>>() : const <Map<String, Object?>>[];

T? _find<T>(List<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}
