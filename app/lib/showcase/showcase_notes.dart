// ショーケースモード（ノートレイン）の純ロジック。
// 配置（placements）を絶対 tick のノート列へ flatten し、表示音域と表示ウィンドウを決める。
// 配置の中でのクリップの繰り返しと切り詰めは、コアの再生（core/src/playback.cpp）と揃える：
// クリップは lengthTicks ごとに繰り返され、ノートは繰り返しの境界と配置の終わりで切れる。
import '../model/project.dart';

/// レインに流すノート1つ（絶対 tick、[startTick, endTick)）
class RainNote {
  const RainNote({
    required this.startTick,
    required this.endTick,
    required this.pitch,
    required this.trackIndex,
    required this.trackId,
    required this.drum,
    required this.velocity,
  });

  final int startTick;
  final int endTick;
  final int pitch;

  /// プロジェクトのトラック順（色パレットの添字）
  final int trackIndex;
  final int trackId;

  /// ドラムキットのトラックか（短いブロックで描く）
  final bool drum;
  final double velocity;

  int get lengthTicks => endTick - startTick;

  @override
  bool operator ==(Object other) =>
      other is RainNote &&
      other.startTick == startTick &&
      other.endTick == endTick &&
      other.pitch == pitch &&
      other.trackIndex == trackIndex &&
      other.trackId == trackId &&
      other.drum == drum &&
      other.velocity == velocity;

  @override
  int get hashCode => Object.hash(startTick, endTick, pitch, trackIndex, trackId, drum, velocity);
}

/// flatten の結果一式
class ShowcaseNotes {
  const ShowcaseNotes({
    required this.notes,
    required this.maxLengthTicks,
    required this.minPitch,
    required this.maxPitch,
    required this.totalTicks,
  });

  /// startTick 昇順（同点は pitch 昇順）
  final List<RainNote> notes;

  /// 最長のノートの長さ（ウィンドウ絞り込みの後方スキャンに使う）
  final int maxLengthTicks;

  /// 表示音域（ノートの実音域に前後2半音のパディングを付け、最低1オクターブ幅にしたもの）
  final int minPitch;
  final int maxPitch;

  /// 曲全体の長さ（tick）。配置が1つも無い曲では1小節
  final int totalTicks;

  bool get isEmpty => notes.isEmpty;
}

/// そのトラックが実際に鳴るか（ミュートでなく、ソロがあればソロのうちの1つ）。
/// コアのミキサーと同じ考え方で、レインも鳴らないトラックは流さない
bool showcaseTrackAudible(ProjectData project, TrackData track) {
  if (track.mixer.mute) return false;
  final anySolo = project.tracks.any((t) => t.mixer.solo);
  return !anySolo || track.mixer.solo;
}

/// プロジェクトの配置を絶対 tick のノート列へ flatten する。
/// [trackId] を渡すとそのトラックだけ。鳴らないトラック（ミュート／ソロ外）は含めない。
ShowcaseNotes flattenShowcaseNotes(ProjectData project, {int? trackId}) {
  final tpb = project.ticksPerBar;
  final trackIndexById = {for (var i = 0; i < project.tracks.length; i++) project.tracks[i].id: i};
  final notes = <RainNote>[];
  var maxLength = 0;

  for (final pl in project.placements) {
    if (trackId != null && pl.trackId != trackId) continue;
    final track = project.track(pl.trackId);
    final clip = project.clip(pl.clipId);
    if (track == null || clip == null || clip.lengthTicks <= 0 || pl.lengthBars <= 0) continue;
    if (!showcaseTrackAudible(project, track)) continue;
    final start = pl.startBar * tpb;
    final end = start + pl.lengthBars * tpb;
    // コアと同じく、クリップを繰り返しながら配置の終わりまで敷く
    for (var rep = start; rep < end; rep += clip.lengthTicks) {
      for (final n in clip.notes) {
        if (n.tick < 0 || n.tick >= clip.lengthTicks || n.length <= 0 || n.pitch < 0 || n.pitch > 127) continue;
        final on = rep + n.tick;
        if (on >= end) continue;
        var off = on + n.length;
        final repEnd = rep + clip.lengthTicks;
        if (off > repEnd) off = repEnd;
        if (off > end) off = end;
        if (off <= on) continue;
        notes.add(RainNote(
          startTick: on,
          endTick: off,
          pitch: n.pitch,
          trackIndex: trackIndexById[track.id] ?? 0,
          trackId: track.id,
          drum: track.isKit,
          velocity: n.velocity,
        ));
        if (off - on > maxLength) maxLength = off - on;
      }
    }
  }

  notes.sort((a, b) {
    final byStart = a.startTick.compareTo(b.startTick);
    return byStart != 0 ? byStart : a.pitch.compareTo(b.pitch);
  });

  final (minPitch, maxPitch) = showcasePitchRange(notes);
  final totalBars = project.lengthBars;
  return ShowcaseNotes(
    notes: notes,
    maxLengthTicks: maxLength,
    minPitch: minPitch,
    maxPitch: maxPitch,
    totalTicks: (totalBars > 0 ? totalBars : 1) * tpb,
  );
}

/// ノート列の実音域から表示音域を決める。前後2半音のパディング付き、最低1オクターブ幅。
/// ノートが無ければ C3〜B3（48〜71）
(int, int) showcasePitchRange(List<RainNote> notes) {
  if (notes.isEmpty) return (48, 71);
  var lo = 127;
  var hi = 0;
  for (final n in notes) {
    if (n.pitch < lo) lo = n.pitch;
    if (n.pitch > hi) hi = n.pitch;
  }
  lo -= 2;
  hi += 2;
  if (hi - lo < 11) {
    // 1オクターブ幅に広げる（中央寄せ、端は 0〜127 に収める）
    final mid = (lo + hi) ~/ 2;
    lo = mid - 5;
    hi = mid + 6;
  }
  if (lo < 0) {
    hi -= lo;
    lo = 0;
  }
  if (hi > 127) {
    lo -= hi - 127;
    hi = 127;
  }
  if (lo < 0) lo = 0;
  return (lo, hi);
}

/// [fromTick, toTick) にかかるノートだけを返す（startTick 昇順のまま）。
/// [notes] は [flattenShowcaseNotes] の結果（startTick 昇順）で、[maxLengthTicks] はその最大長。
List<RainNote> showcaseWindow(List<RainNote> notes, int maxLengthTicks, int fromTick, int toTick) {
  if (notes.isEmpty || toTick <= fromTick) return const [];
  // startTick < toTick の範囲の末尾を二分探索で見つける
  var lo = 0;
  var hi = notes.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (notes[mid].startTick < toTick) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  // 末尾から、手前に長く伸びるノートがありうる範囲まで戻って拾う
  final result = <RainNote>[];
  final scanFloor = fromTick - maxLengthTicks;
  for (var i = lo - 1; i >= 0; i--) {
    final n = notes[i];
    if (n.startTick <= scanFloor && n.endTick <= fromTick) break;
    if (n.endTick > fromTick) result.add(n);
  }
  return result.reversed.toList(growable: false);
}

/// tick を秒に直す（テンポは BPM＝1分あたりの拍数）
double showcaseTickToSeconds(int tick, double tempo) =>
    tempo <= 0 ? 0 : tick / ticksPerBeat * 60 / tempo;

/// 経過時間の表示（m:ss）
String showcaseClock(int tick, double tempo) {
  final totalSeconds = showcaseTickToSeconds(tick, tempo).round();
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
