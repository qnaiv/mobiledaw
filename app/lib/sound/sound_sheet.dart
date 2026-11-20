// 音色シート：トラック名タップで出る。楽器（VSTi のように選ぶ）→ プリセット（セレクトボックス）
// → 楽器専用パネル → エフェクト チェーン（常時表示）→ 大きいつまみ → 詳細ページ（セグメント切替）。
// つまみは再生しながら動かせて、離すまでが1回の Undo。
// 折りたたみ（ExpansionTile）は使わない：チェーンも詳細も開かずに見えるのが Phase 3.5 の再編方針。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../arrange/mixer_sheet.dart';
import '../arrange/song_controller.dart';
import '../arrange/timeline_math.dart';
import '../engine/mdaw_ffi.dart';
import '../kits/kit_store.dart';
import '../kits/kits_screen.dart';
import '../model/project.dart';
import '../ui/theme.dart';
import 'bounce_section.dart';
import 'fx_detail.dart';
import 'granularize_section.dart';
import 'sound_params.dart';
import 'wave_painters.dart';
import 'waveform_peaks.dart';
import 'widgets/fx_painters.dart';
import 'widgets/param_knob.dart';
import 'widgets/segment_chips.dart';

Future<void> showSoundSheet(BuildContext context, SongController song, int trackId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DawColors.panel,
    builder: (context) => _SoundSheet(song: song, trackId: trackId),
  );
}

/// シートの先頭に置く小さな再生バー：シートを開いたまま曲全体を再生・停止して、
/// つまみの効きをその場で確かめられるようにする（操作は SongController の従来どおり）
class _SheetTransport extends StatefulWidget {
  const _SheetTransport({required this.song});

  final SongController song;

  @override
  State<_SheetTransport> createState() => _SheetTransportState();
}

class _SheetTransportState extends State<_SheetTransport> with SingleTickerProviderStateMixin {
  final _position = ValueNotifier<int>(0);
  final _playing = ValueNotifier<bool>(false);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      _position.value = widget.song.engine.positionTicks;
      _playing.value = widget.song.engine.isPlaying;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _position.dispose();
    _playing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: DawColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DawColors.line),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '先頭へ',
            onPressed: song.rewind,
            icon: const Icon(Icons.skip_previous, size: 20),
          ),
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListenableBuilder(
                listenable: Listenable.merge([_position, _playing]),
                builder: (context, _) => FilledButton(
                  onPressed: song.togglePlay,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_playing.value ? Icons.stop : Icons.play_arrow,
                          size: 18, semanticLabel: _playing.value ? '止める' : '再生'),
                      const SizedBox(width: 6),
                      Text(formatPosition(_position.value, song.project.ticksPerBar),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '元に戻す',
            onPressed: song.canUndo ? song.undo : null,
            icon: const Icon(Icons.undo, size: 20),
          ),
          IconButton(
            tooltip: 'やり直す',
            onPressed: song.canRedo ? song.redo : null,
            icon: const Icon(Icons.redo, size: 20),
          ),
        ],
      ),
    );
  }
}

/// 楽器の識別子と見た目（モックアップで決めた色分け）
const _kAnalog = 'analog';
const _kWavetable = 'wt';
const _kKit = 'kit';
const _kSampler = 'sampler';

const _instNames = {_kAnalog: 'アナログ・シンセ', _kWavetable: 'ウェーブテーブル', _kKit: 'ドラムキット', _kSampler: 'サンプラー'};
const _instColors = {_kAnalog: Color(0xFFF0A13C), _kWavetable: Color(0xFF35C4B5), _kKit: Color(0xFFE879C6), _kSampler: Color(0xFF7FB2F0)};

/// トラックが今どの楽器か（キット優先、シンセは wtTable で判定）
/// トラックが今どの楽器か（サンプラー優先、次にキット、シンセは wtTable で判定）
String _instrumentOf(TrackData t) {
  if (t.isSampler) return _kSampler;
  if (t.isKit) return _kKit;
  return (t.synth['wtTable'] ?? 0) >= 1 ? _kWavetable : _kAnalog;
}

SoundParam _paramOf(String key) => allSoundParams.firstWhere((p) => p.key == key);

/// 音色シートが SongController に求める読み書き面。シートの中身（パネル群）は
/// この面だけに依存させ、ウィジェットテストではフェイクに差し替えられるようにする
/// （Phase 3 の FxUnitControls と同じ分離。エンジン FFI には触れない）。
abstract class SoundSheetActions {
  ProjectData get project;
  KitStore get kits;

  /// 値が変わったときに鳴る通知（詳細シート等の再描画用）
  Listenable get changes;
  bool get canUndo;
  bool get canRedo;
  void undo();
  void redo();
  void beginGesture();
  void endGesture();
  bool setSound(int trackId, int paramId, double value);
  void setSounds(int trackId, Map<int, double> values);
  void previewTrack(int trackId);
  void auditionChord(List<int> notes);
  void auditionSequence(List<List<int>> chords, {Duration each});
  void audition(int pitch, {double velocity});
  bool setTrackKit(int trackId, String kitId);
  bool setTrackSampler(int trackId, String kitId, String soundName, int rootNote, double gain, double start);
  bool setTrackSamplerParam(int trackId, int paramId, double value);
  bool addFxUnit(int trackId, int unitType);
  bool removeFxUnit(int trackId, int unitIndex);
  bool moveFxUnit(int trackId, int fromIndex, int toIndex);
  bool setFxUnitEnabled(int trackId, int unitIndex, bool enabled);
  bool setFxUnitParam(int trackId, int unitIndex, int paramId, double value);
}

/// 本番用：SongController へそのまま委譲する
class SongSoundActions implements SoundSheetActions {
  const SongSoundActions(this.song);

  final SongController song;

  @override
  ProjectData get project => song.project;
  @override
  KitStore get kits => song.kits;
  @override
  Listenable get changes => song;
  @override
  bool get canUndo => song.canUndo;
  @override
  bool get canRedo => song.canRedo;
  @override
  void undo() => song.undo();
  @override
  void redo() => song.redo();
  @override
  void beginGesture() => song.beginGesture();
  @override
  void endGesture() => song.endGesture();
  @override
  bool setSound(int trackId, int paramId, double value) => song.setSound(trackId, paramId, value);
  @override
  void setSounds(int trackId, Map<int, double> values) => song.setSounds(trackId, values);
  @override
  void previewTrack(int trackId) => song.previewTrack(trackId);
  @override
  void auditionChord(List<int> notes) => song.auditionChord(notes);
  @override
  void auditionSequence(List<List<int>> chords, {Duration each = const Duration(milliseconds: 600)}) =>
      song.auditionSequence(chords, each: each);
  @override
  void audition(int pitch, {double velocity = 0.8}) => song.audition(pitch, velocity: velocity);
  @override
  bool setTrackKit(int trackId, String kitId) => song.setTrackKit(trackId, kitId);
  @override
  bool setTrackSampler(int trackId, String kitId, String soundName, int rootNote, double gain, double start) =>
      song.setTrackSampler(trackId, kitId, soundName, rootNote, gain, start);
  @override
  bool setTrackSamplerParam(int trackId, int paramId, double value) => song.setTrackSamplerParam(trackId, paramId, value);
  @override
  bool addFxUnit(int trackId, int unitType) => song.addFxUnit(trackId, unitType);
  @override
  bool removeFxUnit(int trackId, int unitIndex) => song.removeFxUnit(trackId, unitIndex);
  @override
  bool moveFxUnit(int trackId, int fromIndex, int toIndex) => song.moveFxUnit(trackId, fromIndex, toIndex);
  @override
  bool setFxUnitEnabled(int trackId, int unitIndex, bool enabled) => song.setFxUnitEnabled(trackId, unitIndex, enabled);
  @override
  bool setFxUnitParam(int trackId, int unitIndex, int paramId, double value) =>
      song.setFxUnitParam(trackId, unitIndex, paramId, value);
}

class _SoundSheet extends StatelessWidget {
  const _SoundSheet({required this.song, required this.trackId});

  final SongController song;
  final int trackId;

  Future<void> _pickKit(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<String>(builder: (_) => KitsScreen(song: song, pickFor: trackId)));
    song.previewTrack(trackId);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: ListenableBuilder(
          listenable: song,
          builder: (context, _) {
            final track = song.project.track(trackId);
            if (track == null) return const SizedBox(height: 120, child: Center(child: Text('トラックがありません')));
            return SoundSheetContent(
              actions: SongSoundActions(song),
              track: track,
              onBrowseKit: () => _pickKit(context),
              onOpenMixer: () => showMixerSheet(context, song, focusTrackId: trackId),
              // シートを開いたまま曲を再生・停止できる小さな再生バー
              header: _SheetTransport(song: song),
              bounceSection: BounceSection(song: song, track: track),
              granularizeSection: GranularizeSection(song: song, track: track),
            );
          },
        ),
      ),
    );
  }
}

/// 音色シートの中身（再生バーを除く本体）。並びは全楽器共通で
/// [楽器カード] → [音源パネル] → [エフェクト チェーン（常時表示）] → [マクロ] →
/// [詳細ページ（シンセのみ）] → [パンプ・センド]。
/// テストからはフェイクの [actions] で直接 pump できる。
class SoundSheetContent extends StatelessWidget {
  const SoundSheetContent({
    super.key,
    required this.actions,
    required this.track,
    required this.onBrowseKit,
    required this.onOpenMixer,
    this.header,
    this.bounceSection,
    this.granularizeSection,
  });

  final SoundSheetActions actions;
  final TrackData track;
  final VoidCallback onBrowseKit;
  final VoidCallback onOpenMixer;

  /// 先頭に出す再生バー（本番は _SheetTransport。テストでは省略可）
  final Widget? header;

  /// サンプラーパネル末尾に出すバウンス節（本番は BounceSection。テストでは省略可）
  final Widget? bounceSection;

  /// 末尾に出すグラニュラー化節（本番は GranularizeSection。サンプラー以外で表示。
  /// テストでは省略可）
  final Widget? granularizeSection;

  void _audition() {
    if (track.isSampler) {
      // サンプラーは基準音程を中心に短い和音で試聴（エンジン側でスロットのサンプラーが鳴る）
      final root = track.samplerRootNote;
      actions.auditionChord([root, root + 4, root + 7]);
      return;
    }
    actions.previewTrack(track.id);
    final kit = track.isKit ? actions.kits.installed(track.kitId) : null;
    if (kit != null) {
      // キットは最初の数音を順に
      actions.auditionSequence([for (final n in kit.notes.take(4)) [n]], each: const Duration(milliseconds: 280));
    } else {
      actions.auditionChord(const [60, 63, 67, 70]);
    }
  }

  void _selectInstrument(BuildContext context, String inst) {
    if (inst == _instrumentOf(track)) return;
    if (inst == _kSampler) {
      // 入っているキットがあれば最初のキットの最初の音、無ければ探す画面へ
      final have = actions.kits.installedKits();
      if (have.isEmpty) {
        onBrowseKit();
      } else {
        final kit = have.first;
        actions.setTrackSampler(track.id, kit.id, kit.sounds.isEmpty ? '' : kit.sounds.first.name, 60, 1.0, 0.0);
        actions.previewTrack(track.id);
      }
      return;
    }
    // サンプラーから他の楽器へ移るときはサンプラーを外す（設定はコア側に残らないので注意：
    // 再度サンプラーを選ぶと既定値から。キット／シンセの設定は従来どおり残る）
    if (track.isSampler) {
      actions.setTrackSampler(track.id, '', '', 60, 1.0, 0.0);
    }
    if (inst == _kKit) {
      // 入っているキットがあれば最初のもの、無ければ探す画面へ
      final have = actions.kits.installedKits();
      if (have.isEmpty) {
        onBrowseKit();
      } else {
        actions.setTrackKit(track.id, have.first.id);
        actions.previewTrack(track.id);
      }
      return;
    }
    if (track.isKit) actions.setTrackKit(track.id, '');
    if (inst == _kAnalog) {
      actions.setSound(track.id, MdawParam.wtTable, 0);
    } else if ((track.synth['wtTable'] ?? 0) < 1) {
      actions.setSound(track.id, MdawParam.wtTable, 1);
    }
    actions.previewTrack(track.id);
  }

  @override
  Widget build(BuildContext context) {
    final inst = _instrumentOf(track);
    final instColor = _instColors[inst]!;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: Color(track.color), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${track.name} の音色',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(border: Border.all(color: instColor), borderRadius: BorderRadius.circular(999)),
              child: Text(_instNames[inst]!, style: TextStyle(fontSize: 10, color: instColor, fontWeight: FontWeight.w700)),
            ),
            IconButton(tooltip: '試聴', onPressed: _audition, icon: const Icon(Icons.play_circle_outline)),
            IconButton(
              tooltip: 'ミキサー',
              onPressed: onOpenMixer,
              icon: const Icon(Icons.tune),
            ),
            IconButton(
              tooltip: '元に戻す',
              onPressed: actions.canUndo ? actions.undo : null,
              icon: const Icon(Icons.undo),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const _Caption('楽器'),
        Row(
          children: [
            _InstCard(
              icon: Icons.graphic_eq,
              name: 'アナログ',
              sub: 'のこぎり／矩形',
              color: _instColors[_kAnalog]!,
              selected: inst == _kAnalog,
              onTap: () => _selectInstrument(context, _kAnalog),
            ),
            const SizedBox(width: 8),
            _InstCard(
              icon: Icons.waves,
              name: 'ウェーブテーブル',
              sub: '波形が変化',
              color: _instColors[_kWavetable]!,
              selected: inst == _kWavetable,
              onTap: () => _selectInstrument(context, _kWavetable),
            ),
            const SizedBox(width: 8),
            _InstCard(
              icon: Icons.grid_view,
              name: 'ドラムキット',
              sub: 'パッドで鳴らす',
              color: _instColors[_kKit]!,
              selected: inst == _kKit,
              onTap: () => _selectInstrument(context, _kKit),
            ),
            const SizedBox(width: 8),
            _InstCard(
              icon: Icons.music_note,
              name: 'サンプラー',
              sub: '音を鍵盤で',
              color: _instColors[_kSampler]!,
              selected: inst == _kSampler,
              onTap: () => _selectInstrument(context, _kSampler),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (inst == _kSampler) ...[
          _SamplerPanel(actions: actions, track: track, onBrowse: onBrowseKit, bounceSection: bounceSection),
          const SizedBox(height: 12),
          _FxChainSection(actions: actions, track: track),
          const SizedBox(height: 8),
          for (final m in soundMacros.where((m) => m.label == 'パンプ')) _MacroSlider(actions: actions, track: track, macro: m),
          _PumpSendSection(actions: actions, track: track),
        ] else if (inst == _kKit) ...[
          _KitPanel(actions: actions, track: track, onBrowse: onBrowseKit),
          const SizedBox(height: 12),
          _FxChainSection(actions: actions, track: track),
          const SizedBox(height: 8),
          for (final m in soundMacros.where((m) => m.label == 'パンプ')) _MacroSlider(actions: actions, track: track, macro: m),
          _PumpSendSection(actions: actions, track: track),
        ] else if (inst == _kWavetable) ...[
          _WavetablePanel(actions: actions, track: track),
        ] else ...[
          _AnalogPanel(actions: actions, track: track),
        ],
        // グラニュラー化の入口は素材化したいトラック側に置く（サンプラーは
        // パネル内のバウンス節が入口なので除く）
        if (inst != _kSampler && granularizeSection != null) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          granularizeSection!,
        ],
      ],
    );
  }
}

/// 楽器カード（選択中は楽器色の枠）
class _InstCard extends StatelessWidget {
  const _InstCard({required this.icon, required this.name, required this.sub, required this.color, required this.selected, required this.onTap});

  final IconData icon;
  final String name;
  final String sub;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: DawColors.background,
            border: Border.all(color: selected ? color : DawColors.line, width: selected ? 1.6 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: selected ? color : DawColors.muted),
              const SizedBox(height: 3),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: DawColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// プリセットのセレクトボックス（楽器に合うものだけ。現在の値と一致すればそれが選ばれて見える）
class _PresetSelect extends StatelessWidget {
  const _PresetSelect({required this.actions, required this.track, required this.presets});

  final SoundSheetActions actions;
  final TrackData track;
  final List<SoundPreset> presets;

  SoundPreset? _current() {
    for (final p in presets) {
      var match = true;
      for (final prm in allSoundParams) {
        if ((prm.valueOf(track) - (p.allValues[prm.id] ?? prm.def)).abs() > 0.01) {
          match = false;
          break;
        }
      }
      if (match) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final current = _current();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Caption('プリセット'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: DawColors.line), borderRadius: BorderRadius.circular(10)),
          child: DropdownButton<String>(
            isExpanded: true,
            underline: const SizedBox.shrink(),
            value: current?.name,
            hint: const Text('プリセットを選ぶ', style: TextStyle(fontSize: 13, color: DawColors.muted)),
            items: [
              for (final p in presets) DropdownMenuItem(value: p.name, child: Text('${p.name}（${p.category}）', style: const TextStyle(fontSize: 13))),
            ],
            onChanged: (name) {
              if (name == null) return;
              final p = presets.firstWhere((e) => e.name == name);
              actions.setSounds(track.id, p.allValues);
              actions.previewTrack(track.id);
              actions.auditionChord(p.category == 'ドラム' ? const [48] : const [60, 63, 67, 70]);
            },
          ),
        ),
      ],
    );
  }
}

/// シンセ共通の後半の並び：[エフェクト チェーン] → [大きいつまみ] → [詳細ページ] → [パンプ・センド]
List<Widget> _synthTail({
  required SoundSheetActions actions,
  required TrackData track,
  required Color color,
  required bool wavetable,
}) {
  return [
    const SizedBox(height: 12),
    _FxChainSection(actions: actions, track: track),
    const SizedBox(height: 8),
    const _Caption('大きいつまみ'),
    for (final m in soundMacros) _MacroSlider(actions: actions, track: track, macro: m),
    const SizedBox(height: 12),
    _SynthDetailPages(actions: actions, track: track, color: color, wavetable: wavetable),
    _PumpSendSection(actions: actions, track: track),
  ];
}

/// アナログ・シンセの専用パネル（アンバー：波形・フィルター特性・ADSR が見える）
class _AnalogPanel extends StatelessWidget {
  const _AnalogPanel({required this.actions, required this.track});

  final SoundSheetActions actions;
  final TrackData track;

  @override
  Widget build(BuildContext context) {
    final color = _instColors[_kAnalog]!;
    final wave = _paramOf('wave');
    final cutoff = _paramOf('cutoffHz');
    final res = _paramOf('resonance');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetSelect(actions: actions, track: track, presets: [for (final p in soundPresets) if (!p.isWavetable) p]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(border: Border.all(color: DawColors.line), borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ANALOG', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: color)),
              _ParamRow(actions: actions, track: track, param: wave),
              CustomPaint(
                size: const Size.fromHeight(72),
                painter: AnalogWavePainter(
                  square: wave.valueOf(track) >= 0.5,
                  unison: _paramOf('unison').valueOf(track).round(),
                  color: color,
                  dim: DawColors.muted,
                ),
              ),
              const _Caption('フィルター特性'),
              CustomPaint(
                size: const Size.fromHeight(52),
                painter: FilterCurvePainter(
                  cutoffUnit: cutoff.toUnit(cutoff.valueOf(track)),
                  resUnit: res.toUnit(res.valueOf(track)),
                  color: color,
                  dim: DawColors.muted,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 18,
                  children: [
                    _SynthKnob(actions: actions, track: track, param: cutoff, label: 'カットオフ', color: color),
                    _SynthKnob(actions: actions, track: track, param: res, label: 'レゾナンス', color: color),
                  ],
                ),
              ),
              const _Caption('エンベロープ（ADSR）'),
              CustomPaint(
                size: const Size.fromHeight(52),
                painter: AdsrPainter(
                  a: _paramOf('attackS').toUnit(_paramOf('attackS').valueOf(track)),
                  d: _paramOf('decayS').toUnit(_paramOf('decayS').valueOf(track)),
                  s: _paramOf('sustain').valueOf(track),
                  r: _paramOf('releaseS').toUnit(_paramOf('releaseS').valueOf(track)),
                  color: color,
                  dim: DawColors.muted,
                ),
              ),
            ],
          ),
        ),
        ..._synthTail(actions: actions, track: track, color: color, wavetable: false),
      ],
    );
  }
}

/// ウェーブテーブル・シンセの専用パネル（ティール：波形モーフが見える）
class _WavetablePanel extends StatelessWidget {
  const _WavetablePanel({required this.actions, required this.track});

  final SoundSheetActions actions;
  final TrackData track;

  @override
  Widget build(BuildContext context) {
    final color = _instColors[_kWavetable]!;
    final tableParam = _paramOf('wtTable');
    final posParam = _paramOf('wtPos');
    final warpParam = _paramOf('wtWarp');
    final warpAmtParam = _paramOf('wtWarpAmount');
    final table = tableParam.valueOf(track).round();
    final pos = posParam.valueOf(track);
    final warp = warpParam.valueOf(track).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetSelect(actions: actions, track: track, presets: [for (final p in soundPresets) if (p.isWavetable) p]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(border: Border.all(color: DawColors.line), borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('WAVETABLE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: color)),
              const SizedBox(height: 6),
              CustomPaint(
                size: const Size.fromHeight(104),
                painter: WtWavePainter(
                  table: table,
                  pos: pos,
                  warp: warp,
                  warpAmt: warpAmtParam.valueOf(track),
                  color: color,
                  ghost: DawColors.muted,
                ),
              ),
              CustomPaint(
                size: const Size.fromHeight(22),
                painter: WtStripPainter(table: table, pos: pos, color: color, dim: DawColors.muted),
              ),
              const _Caption('テーブル'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (id, name) in wtTableNames)
                    _MiniChip(
                      label: name,
                      color: color,
                      selected: table == id,
                      onTap: () => actions.setSound(track.id, MdawParam.wtTable, id.toDouble()),
                    ),
                ],
              ),
              _ParamRow(actions: actions, track: track, param: posParam),
              const _Caption('ワープ'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (id, name) in const [(0, 'なし'), (1, '曲げる'), (2, '絞る'), (3, 'シンク')])
                    _MiniChip(
                      label: name,
                      color: color,
                      selected: warp == id,
                      onTap: () => actions.setSound(track.id, MdawParam.wtWarp, id.toDouble()),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 18,
                  children: [
                    _SynthKnob(actions: actions, track: track, param: warpAmtParam, label: 'ワープ量', color: color),
                  ],
                ),
              ),
              const _Caption('テーブルの位置を揺らす（LFO）'),
              _ParamRow(actions: actions, track: track, param: _paramOf('wtLfoRate')),
              _ParamRow(actions: actions, track: track, param: _paramOf('wtLfoAmount')),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('カスタム波形（WAVを読み込む／波形を描く）は準備中です', style: TextStyle(fontSize: 11, color: DawColors.muted)),
              ),
            ],
          ),
        ),
        ..._synthTail(actions: actions, track: track, color: color, wavetable: true),
      ],
    );
  }
}

/// シンセの詳細ページ（旧「詳しく：〜」折りたたみ群の置き換え、Phase 3.5）。
/// セグメントで [音源|フィルター|エンベロープ|LFO|演奏] を切り替え、各ページは
/// 視覚要素（波形／カーブ／グラフ）＋ノブ主体のレイアウトにする。
/// 旧セクションのパラメータは全てどこかのページに置く（対応は PHASE35-HANDOFF 参照）。
class _SynthDetailPages extends StatefulWidget {
  const _SynthDetailPages({required this.actions, required this.track, required this.color, required this.wavetable});

  final SoundSheetActions actions;
  final TrackData track;
  final Color color;
  final bool wavetable;

  @override
  State<_SynthDetailPages> createState() => _SynthDetailPagesState();
}

class _SynthDetailPagesState extends State<_SynthDetailPages> {
  int _page = 0;

  SoundSheetActions get actions => widget.actions;
  TrackData get track => widget.track;
  Color get color => widget.color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(border: Border.all(color: DawColors.line), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('DETAIL', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: color)),
          const SizedBox(height: 8),
          SegmentChips(
            options: const [(0, '音源'), (1, 'フィルター'), (2, 'エンベロープ'), (3, 'LFO'), (4, '演奏')],
            selected: _page,
            color: color,
            onSelected: (v) => setState(() => _page = v),
          ),
          const SizedBox(height: 6),
          switch (_page) {
            0 => _oscPage(),
            1 => _filterPage(),
            2 => _envPage(),
            3 => _lfoPage(),
            _ => _playPage(),
          },
        ],
      ),
    );
  }

  /// 音源ページ：波形＋ユニゾン系ノブ＋FM・フォルマント
  /// （旧「詳しく：オシレーター／ユニゾン」＋「詳しく：FM・フォルマント」）
  Widget _oscPage() {
    final wave = _paramOf('wave');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.wavetable)
          CustomPaint(
            size: const Size.fromHeight(64),
            painter: WtWavePainter(
              table: _paramOf('wtTable').valueOf(track).round(),
              pos: _paramOf('wtPos').valueOf(track),
              warp: _paramOf('wtWarp').valueOf(track).round(),
              warpAmt: _paramOf('wtWarpAmount').valueOf(track),
              color: color,
              ghost: DawColors.muted,
            ),
          )
        else
          CustomPaint(
            size: const Size.fromHeight(56),
            painter: AnalogWavePainter(
              square: wave.valueOf(track) >= 0.5,
              unison: _paramOf('unison').valueOf(track).round(),
              color: color,
              dim: DawColors.muted,
            ),
          ),
        _KnobRow(
          actions: actions,
          track: track,
          color: color,
          knobs: widget.wavetable
              ? const [('unison', '本数'), ('detuneCents', 'ずらし幅'), ('width', '広がり'), ('blend', 'ブレンド')]
              : const [
                  ('unison', '本数'),
                  ('detuneCents', 'ずらし幅'),
                  ('width', '広がり'),
                  ('blend', 'ブレンド'),
                  ('osc', 'オシレーター'),
                  ('sub', 'サブ'),
                  ('noise', 'ノイズ'),
                  ('drive', '歪み'),
                ],
        ),
        const _Caption('FM・フォルマント'),
        _KnobRow(
          actions: actions,
          track: track,
          color: color,
          knobs: const [('fm', 'FMの深さ'), ('fmRatio', '周波数比'), ('formant', 'フォルマント')],
        ),
        Row(
          children: [
            const SizedBox(width: 130, child: Text('母音', style: TextStyle(fontSize: 12))),
            SegmentChips(
              options: const [(0, 'ア'), (1, 'エ'), (2, 'イ'), (3, 'オ'), (4, 'ウ')],
              selected: _paramOf('formantVowel').valueOf(track).round(),
              color: color,
              onSelected: (v) => actions.setSound(track.id, MdawParam.formantVowel, v.toDouble()),
            ),
          ],
        ),
      ],
    );
  }

  /// フィルターページ：特性カーブ＋全パラメータをノブで（旧「詳しく：フィルター」）
  Widget _filterPage() {
    final cutoff = _paramOf('cutoffHz');
    final res = _paramOf('resonance');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          size: const Size.fromHeight(64),
          painter: FilterCurvePainter(
            cutoffUnit: cutoff.toUnit(cutoff.valueOf(track)),
            resUnit: res.toUnit(res.valueOf(track)),
            color: color,
            dim: DawColors.muted,
          ),
        ),
        _KnobRow(
          actions: actions,
          track: track,
          color: color,
          knobs: const [
            ('cutoffHz', 'カットオフ'),
            ('resonance', 'レゾナンス'),
            ('filterEnv', '開く量'),
            ('filterEnvDecayS', '閉じる時間'),
            ('keyTrack', 'キートラック'),
          ],
        ),
      ],
    );
  }

  /// エンベロープページ：ADSR グラフ＋ノブ（旧「詳しく：エンベロープ」）
  Widget _envPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          size: const Size.fromHeight(64),
          painter: AdsrPainter(
            a: _paramOf('attackS').toUnit(_paramOf('attackS').valueOf(track)),
            d: _paramOf('decayS').toUnit(_paramOf('decayS').valueOf(track)),
            s: _paramOf('sustain').valueOf(track),
            r: _paramOf('releaseS').toUnit(_paramOf('releaseS').valueOf(track)),
            color: color,
            dim: DawColors.muted,
          ),
        ),
        _KnobRow(
          actions: actions,
          track: track,
          color: color,
          knobs: const [('attackS', 'アタック'), ('decayS', 'ディケイ'), ('sustain', 'サステイン'), ('releaseS', 'リリース')],
        ),
        const _Caption('音程エンベロープ・音量'),
        _KnobRow(
          actions: actions,
          track: track,
          color: color,
          knobs: const [('pitchEnv', '音程の動き'), ('pitchEnvDecayS', '戻る時間'), ('masterGain', '音色の音量')],
        ),
      ],
    );
  }

  /// LFO ページ：波形プレビュー＋波形／同期の選択＋宛先ノブ（旧「詳しく：LFO」）
  Widget _lfoPage() {
    final sync = _paramOf('lfoSync').valueOf(track) >= 0.5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          size: const Size.fromHeight(56),
          painter: LfoWavePainter(wave: _paramOf('lfoWave').valueOf(track).round(), color: color, dim: DawColors.muted),
        ),
        const _Caption('LFOの波形'),
        SegmentChips(
          options: const [(0, '正弦'), (1, '三角'), (2, '矩形'), (3, 'のこぎり')],
          selected: _paramOf('lfoWave').valueOf(track).round(),
          color: color,
          onSelected: (v) => actions.setSound(track.id, MdawParam.lfoWave, v.toDouble()),
        ),
        _ParamRow(actions: actions, track: track, param: _paramOf('lfoSync')),
        if (sync) ...[
          const _Caption('LFOの周期（テンポ同期）'),
          SegmentChips(
            options: const [(0, '1小節'), (1, '4分'), (2, '付点8分'), (3, '8分'), (4, '16分')],
            selected: _paramOf('lfoDiv').valueOf(track).round(),
            color: color,
            onSelected: (v) => actions.setSound(track.id, MdawParam.lfoDiv, v.toDouble()),
          ),
        ],
        _KnobRow(
          actions: actions,
          track: track,
          color: color,
          knobs: const [('lfoCutoff', '明るさへ'), ('lfoPitch', '音程へ'), ('lfoAmp', '音量へ')],
        ),
        _ParamRow(actions: actions, track: track, param: _paramOf('lfoRetrig')),
      ],
    );
  }

  /// 演奏ページ：グライドのカーブ＋グライド／モノ（旧「詳しく：演奏」）
  Widget _playPage() {
    final glide = _paramOf('glideS');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          size: const Size.fromHeight(64),
          painter: GlidePainter(glideUnit: glide.toUnit(glide.valueOf(track)), color: color, dim: DawColors.muted),
        ),
        _KnobRow(
          actions: actions,
          track: track,
          color: color,
          knobs: const [('glideS', 'グライド')],
        ),
        _ParamRow(actions: actions, track: track, param: _paramOf('mono')),
      ],
    );
  }
}

/// 小さいチップ（テーブル／ワープの選択用）
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color, required this.selected, required this.onTap});

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          border: Border.all(color: selected ? color : DawColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? const Color(0xFF111214) : DawColors.text)),
      ),
    );
  }
}

/// キットのトラック：使っているキット、パッド（タップで試聴）、別のキットに替える
class _KitPanel extends StatelessWidget {
  const _KitPanel({required this.actions, required this.track, required this.onBrowse});

  final SoundSheetActions actions;
  final TrackData track;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final kit = actions.kits.installed(track.kitId);
    final installed = actions.kits.installedKits();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: installed.isEmpty
                  ? const Text('ダウンロード済みのキットがありません', style: TextStyle(color: DawColors.muted))
                  : DropdownButton<String>(
                      isExpanded: true,
                      value: kit != null ? track.kitId : null,
                      hint: Text('「${track.kitId}」（未ダウンロード）', style: const TextStyle(color: DawColors.danger)),
                      items: [
                        for (final k in installed) DropdownMenuItem(value: k.id, child: Text('${k.name}（${k.sounds.length}音）')),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        actions.setTrackKit(track.id, id);
                        actions.previewTrack(track.id);
                      },
                    ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: onBrowse, icon: const Icon(Icons.cloud_download_outlined, size: 18), label: const Text('キットを探す')),
          ],
        ),
        if (kit == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('このキットはまだこの端末にありません。「キットを探す」から入れると鳴ります',
                style: TextStyle(fontSize: 12, color: DawColors.danger)),
          )
        else ...[
          const SizedBox(height: 8),
          const _Caption('パッド（タップで試聴。ピアノロールの列になります）'),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.25,
            children: [
              for (final snd in kit.sounds)
                InkWell(
                  onTap: () {
                    actions.previewTrack(track.id);
                    actions.audition(snd.note, velocity: 0.9);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: DawColors.background,
                      border: Border.all(color: DawColors.line),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: Color(track.color), shape: BoxShape.circle),
                        ),
                        Text(snd.name,
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, color: DawColors.muted)),
      );
}

class _MacroSlider extends StatelessWidget {
  const _MacroSlider({required this.actions, required this.track, required this.macro});

  final SoundSheetActions actions;
  final TrackData track;
  final SoundMacro macro;

  @override
  Widget build(BuildContext context) {
    final color = Color(track.color);
    final value = macro.read(track).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(macro.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(macro.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: DawColors.muted)),
              ],
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
              ),
              child: Slider(
                value: value,
                onChangeStart: (_) => actions.beginGesture(),
                onChanged: (u) => actions.setSounds(track.id, macro.write(u)),
                onChangeEnd: (_) => actions.endGesture(),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('${(value * 100).round()}',
                textAlign: TextAlign.right, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}

/// セクション見出し（折りたたみの代わりに、常時表示セクションの題として使う）
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      );
}

/// パンプ・センド節：トラック直属のパラメータ（旧「詳しく：パンプ・センド」）。
/// 折りたたみをやめて常時表示のセクションにした（Phase 3.5）。
class _PumpSendSection extends StatelessWidget {
  const _PumpSendSection({required this.actions, required this.track});

  final SoundSheetActions actions;
  final TrackData track;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('パンプ・センド'),
        for (final p in trackLevelFxParams) _ParamRow(actions: actions, track: track, param: p),
      ],
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow({required this.actions, required this.track, required this.param});

  final SoundSheetActions actions;
  final TrackData track;
  final SoundParam param;

  @override
  Widget build(BuildContext context) {
    final v = param.valueOf(track);
    if (param.scale == ParamScale.toggle) {
      final on = v >= 0.5;
      final labels = param.id == MdawParam.wave ? ('のこぎり', '矩形') : ('オフ', 'オン');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(param.label, style: const TextStyle(fontSize: 13))),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(labels.$1)),
                ButtonSegment(value: true, label: Text(labels.$2)),
              ],
              selected: {on},
              onSelectionChanged: (s) => actions.setSound(track.id, param.id, s.first ? 1 : 0),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(param.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              value: param.toUnit(v),
              onChangeStart: (_) => actions.beginGesture(),
              onChanged: (u) => actions.setSound(track.id, param.id, param.fromUnit(u)),
              onChangeEnd: (_) => actions.endGesture(),
            ),
          ),
          GestureDetector(
            // ダブルタップで既定値に戻す
            onDoubleTap: () => actions.setSound(track.id, param.id, param.def),
            child: SizedBox(
              width: 70,
              child: Text(param.format(v),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ),
        ],
      ),
    );
  }
}

/// シンセ系パラメータのノブ（ドラッグ中は1回の Undo にまとめる）
class _SynthKnob extends StatelessWidget {
  const _SynthKnob({required this.actions, required this.track, required this.param, required this.label, required this.color});

  final SoundSheetActions actions;
  final TrackData track;
  final SoundParam param;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = param.valueOf(track);
    return ParamKnob(
      label: label,
      valueText: param.format(v),
      unit: param.toUnit(v),
      color: color,
      onChangeStart: actions.beginGesture,
      onChanged: (u) => actions.setSound(track.id, param.id, param.fromUnit(u)),
      onChangeEnd: (_) => actions.endGesture(),
      onReset: () => actions.setSound(track.id, param.id, param.def),
    );
  }
}

/// ノブの横並び（詳細ページの主要パラメータ用）
class _KnobRow extends StatelessWidget {
  const _KnobRow({required this.actions, required this.track, required this.color, required this.knobs});

  final SoundSheetActions actions;
  final TrackData track;
  final Color color;

  /// (パラメータのキー, ノブ下の短いラベル)
  final List<(String, String)> knobs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        children: [
          for (final (key, label) in knobs)
            _SynthKnob(actions: actions, track: track, param: _paramOf(key), label: label, color: color),
        ],
      ),
    );
  }
}

/// FX チェーン節：ユニットのカード列（色ドット・名前・有効スイッチ・↑↓・削除）と
/// 「＋追加」パレット。常時表示（折りたたみなし）で、音源パネルの直下に置く（Phase 3.5）。
/// カードの名前タップでそのユニットの詳細シートを開く。
class _FxChainSection extends StatelessWidget {
  const _FxChainSection({required this.actions, required this.track});

  final SoundSheetActions actions;
  final TrackData track;

  @override
  Widget build(BuildContext context) {
    final chain = track.fxChain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('エフェクト チェーン'),
        if (chain.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('チェーンはまだありません。「ユニットを追加」から足せます', style: TextStyle(fontSize: 12, color: DawColors.muted)),
          ),
        for (var i = 0; i < chain.length; i++)
          _FxUnitCard(actions: actions, track: track, index: i, isFirst: i == 0, isLast: i == chain.length - 1),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          enabled: chain.length < kMaxFxUnits,
          leading: const Icon(Icons.add, size: 20),
          title: Text(chain.length < kMaxFxUnits ? 'ユニットを追加' : 'ユニットは最大 $kMaxFxUnits 個まで',
              style: const TextStyle(fontSize: 13)),
          onTap: () => _showFxUnitPalette(context, actions, track),
        ),
      ],
    );
  }
}

class _FxUnitCard extends StatelessWidget {
  const _FxUnitCard({required this.actions, required this.track, required this.index, required this.isFirst, required this.isLast});

  final SoundSheetActions actions;
  final TrackData track;
  final int index;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final unit = track.fxChain[index];
    final meta = fxUnitMetaOf(unit.type);
    final color = meta?.color ?? DawColors.muted;
    final name = meta?.name ?? unit.type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: unit.enabled ? color : DawColors.line, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => _showFxUnitDetail(context, actions, track.id, index),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: unit.enabled ? DawColors.text : DawColors.muted)),
              ),
            ),
          ),
          IconButton(
            tooltip: '上へ',
            visualDensity: VisualDensity.compact,
            onPressed: isFirst ? null : () => actions.moveFxUnit(track.id, index, index - 1),
            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
          ),
          IconButton(
            tooltip: '下へ',
            visualDensity: VisualDensity.compact,
            onPressed: isLast ? null : () => actions.moveFxUnit(track.id, index, index + 1),
            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
          ),
          Switch(
            value: unit.enabled,
            onChanged: (v) => actions.setFxUnitEnabled(track.id, index, v),
          ),
          IconButton(
            tooltip: '削除',
            visualDensity: VisualDensity.compact,
            onPressed: () => actions.removeFxUnit(track.id, index),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// 追加パレット：全ユニット種別の一覧（同じ種別も重ねて足せる）
void _showFxUnitPalette(BuildContext context, SoundSheetActions actions, TrackData track) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: DawColors.panel,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _Caption('追加するエフェクト'),
          for (var i = 0; i < fxUnitMetas.length; i++)
            ListTile(
              dense: true,
              leading: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: fxUnitMetas[i].color, shape: BoxShape.circle),
              ),
              title: Text(fxUnitMetas[i].name, style: const TextStyle(fontSize: 13)),
              onTap: () {
                actions.addFxUnit(track.id, i);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    ),
  );
}

void _showFxUnitDetail(BuildContext context, SoundSheetActions actions, int trackId, int index) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DawColors.panel,
    builder: (context) => _FxUnitDetailSheet(actions: actions, trackId: trackId, index: index),
  );
}

/// ユニットの詳細シート：種別ごとの専用レイアウト（FxUnitDetailBody）で出す。
/// 無効なユニットは、値を動かした時点で自動で有効になる。
class _FxUnitDetailSheet extends StatelessWidget {
  const _FxUnitDetailSheet({required this.actions, required this.trackId, required this.index});

  final SoundSheetActions actions;
  final int trackId;
  final int index;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
        child: ListenableBuilder(
          listenable: actions.changes,
          builder: (context, _) {
            final track = actions.project.track(trackId);
            if (track == null || index < 0 || index >= track.fxChain.length) {
              return const SizedBox(height: 120, child: Center(child: Text('ユニットがありません')));
            }
            final unit = track.fxChain[index];
            final meta = fxUnitMetaOf(unit.type);
            final color = meta?.color ?? DawColors.muted;
            final controls = FxUnitControls(
              valueOf: (p) => unit.params[p.key] ?? p.def,
              write: (p, v) {
                // 無効なユニットは、値を動かしたら使えるように自動で有効化する
                if (!unit.enabled) actions.setFxUnitEnabled(track.id, index, true);
                actions.setFxUnitParam(track.id, index, p.id, v);
              },
              beginGesture: actions.beginGesture,
              endGesture: actions.endGesture,
              tempo: actions.project.tempo,
            );
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(meta?.name ?? unit.type,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    Switch(
                      value: unit.enabled,
                      onChanged: (v) => actions.setFxUnitEnabled(track.id, index, v),
                    ),
                  ],
                ),
                if (meta != null) FxUnitDetailBody(meta: meta, controls: controls),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 音名（C4 = 60）
String _noteName(int note) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  final n = note.clamp(0, 127);
  return '${names[n % 12]}${n ~/ 12 - 1}';
}

/// サンプラーのトラック：素材キットと音の選択、基準音程、音量、開始位置。
/// 素材の実波形（取れなければ見本波形）を出し、グラニュラー時は粒の散布も重ねる
class _SamplerPanel extends StatefulWidget {
  const _SamplerPanel({required this.actions, required this.track, required this.onBrowse, this.bounceSection});

  final SoundSheetActions actions;
  final TrackData track;
  final VoidCallback onBrowse;

  /// 末尾のバウンス節（エンジン書き出しに直結するためシート側から渡す。テストでは省略可）
  final Widget? bounceSection;

  @override
  State<_SamplerPanel> createState() => _SamplerPanelState();
}

class _SamplerPanelState extends State<_SamplerPanel> {
  List<double>? _peaks;
  String _peaksKey = '';

  /// グラニュラーの「細かく調整」を開いているか（主面はプリセット＋主要パラメータだけ）
  bool _showGranularDetail = false;

  SoundSheetActions get actions => widget.actions;
  TrackData get track => widget.track;

  @override
  void initState() {
    super.initState();
    _loadPeaks();
  }

  @override
  void didUpdateWidget(_SamplerPanel old) {
    super.didUpdateWidget(old);
    _loadPeaks();
  }

  /// 選択中の素材の実波形を読む（キット／音が変わったときだけ）
  void _loadPeaks() {
    final key = '${track.samplerKitId}/${track.samplerSoundName}';
    if (key == _peaksKey) return;
    _peaksKey = key;
    _peaks = null;
    if (track.samplerKitId.isEmpty || track.samplerSoundName.isEmpty) return;
    final root = actions.kits.root.path;
    unawaited(loadKitSoundPeaks(kitsRootPath: root, kitId: track.samplerKitId, soundName: track.samplerSoundName)
        .then((p) {
      if (mounted && _peaksKey == key) setState(() => _peaks = p);
    }));
  }

  void _commit(String kitId, String soundName, int rootNote, double gain, double start) {
    actions.setTrackSampler(track.id, kitId, soundName, rootNote, gain, start);
    actions.previewTrack(track.id);
  }

  void _granular(int paramId, double value) {
    actions.setTrackSamplerParam(track.id, paramId, value);
    actions.previewTrack(track.id);
  }

  /// プリセット適用: 全パラメータを書いてから 1 回だけ試聴する
  void _granularPreset(SamplerGranularPreset preset) {
    for (final e in preset.values.entries) {
      actions.setTrackSamplerParam(track.id, e.key, e.value);
    }
    actions.previewTrack(track.id);
  }

  String _granularFormat(SoundParam p, double v) {
    switch (p.unit) {
      case '%':
        return '${(v * 100).round()}%';
      case 'ms':
        return '${v.round()}ms';
      case 'st':
        return '${v.toStringAsFixed(1)} st';
      case 'Hz':
        return '${v.toStringAsFixed(2)} Hz';
      default:
        return '${v.round()}';
    }
  }

  SoundParam _sgParam(String key) => samplerGranularParams.firstWhere((p) => p.key == key);

  /// 素材の波形表示（グラニュラー時は粒の散布を重ねる）
  Widget _waveform(Color color) {
    final peaks = _peaks ?? pseudoPeaks(track.samplerSoundName.hashCode);
    final painter = track.samplerGranularEnabled
        ? BufferGrainPainter(
            peaks: peaks,
            positionUnit: track.samplerGranularPosition,
            spray: track.samplerGranularSpray,
            densityUnit: _sgParam('density').toUnit(track.samplerGranularDensity),
            sizeUnit: _sgParam('sizeMs').toUnit(track.samplerGranularSizeMs),
            texture: track.samplerGranularTexture,
            color: color,
            dim: DawColors.muted,
            seed: track.samplerSoundName.hashCode,
          )
        : WaveformPeaksPainter(peaks: peaks, color: color, dim: DawColors.muted, startUnit: track.samplerStart);
    return Container(
      height: 84,
      decoration: BoxDecoration(
        color: DawColors.background,
        border: Border.all(color: DawColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: CustomPaint(painter: painter, child: const SizedBox.expand()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _instColors[_kSampler]!;
    final kit = actions.kits.installed(track.samplerKitId);
    final installed = actions.kits.installedKits();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SAMPLER', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: color)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: installed.isEmpty
                  ? const Text('ダウンロード済みのキットがありません', style: TextStyle(color: DawColors.muted))
                  : DropdownButton<String>(
                      isExpanded: true,
                      value: kit != null ? track.samplerKitId : null,
                      hint: Text('「${track.samplerKitId}」（未ダウンロード）', style: const TextStyle(color: DawColors.danger)),
                      items: [
                        for (final k in installed) DropdownMenuItem(value: k.id, child: Text('${k.name}（${k.sounds.length}音）')),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        final next = actions.kits.installed(id);
                        _commit(id, next == null || next.sounds.isEmpty ? '' : next.sounds.first.name,
                            track.samplerRootNote, track.samplerGain, track.samplerStart);
                      },
                    ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
                onPressed: widget.onBrowse, icon: const Icon(Icons.cloud_download_outlined, size: 18), label: const Text('キットを探す')),
          ],
        ),
        if (kit == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('素材のキットはまだこの端末にありません。「キットを探す」から入れると鳴ります',
                style: TextStyle(fontSize: 12, color: DawColors.danger)),
          )
        else ...[
          const SizedBox(height: 8),
          const _Caption('素材の音（タップで選択＆試聴）'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final snd in kit.sounds)
                _MiniChip(
                  label: snd.name,
                  color: color,
                  selected: track.samplerSoundName == snd.name,
                  onTap: () {
                    _commit(track.samplerKitId, snd.name, track.samplerRootNote, track.samplerGain, track.samplerStart);
                    actions.audition(track.samplerRootNote);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          _waveform(color),
          const SizedBox(height: 8),
          const _Caption('基準音程（この音程で原音の速さで鳴る）'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '1オクターブ下',
                icon: const Icon(Icons.keyboard_double_arrow_down),
                onPressed: () => _commit(track.samplerKitId, track.samplerSoundName,
                    track.samplerRootNote - 12, track.samplerGain, track.samplerStart),
              ),
              IconButton(
                tooltip: '半音下',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _commit(track.samplerKitId, track.samplerSoundName,
                    track.samplerRootNote - 1, track.samplerGain, track.samplerStart),
              ),
              SizedBox(
                width: 76,
                child: Text('${_noteName(track.samplerRootNote)}（${track.samplerRootNote}）',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: '半音上',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _commit(track.samplerKitId, track.samplerSoundName,
                    track.samplerRootNote + 1, track.samplerGain, track.samplerStart),
              ),
              IconButton(
                tooltip: '1オクターブ上',
                icon: const Icon(Icons.keyboard_double_arrow_up),
                onPressed: () => _commit(track.samplerKitId, track.samplerSoundName,
                    track.samplerRootNote + 12, track.samplerGain, track.samplerStart),
              ),
            ],
          ),
          _CommitSlider(
            label: '音量',
            value: track.samplerGain,
            min: 0,
            max: 2,
            format: (v) => '${(v * 100).round()}%',
            onCommit: (v) =>
                _commit(track.samplerKitId, track.samplerSoundName, track.samplerRootNote, v, track.samplerStart),
          ),
          _CommitSlider(
            label: '開始位置',
            value: track.samplerStart,
            min: 0,
            max: 0.95,
            format: (v) => '${(v * 100).round()}%',
            onCommit: (v) =>
                _commit(track.samplerKitId, track.samplerSoundName, track.samplerRootNote, track.samplerGain, v),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('ループはしません。素材が終わるかノートオフ（リリース 60ms）で消えます',
                style: TextStyle(fontSize: 11, color: DawColors.muted)),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Row(
            children: [
              const Expanded(child: _Caption('グラニュラー（素材全体を粒で鳴らす）')),
              Switch(
                value: track.samplerGranularEnabled,
                activeThumbColor: color,
                onChanged: (v) => _granular(MdawParam.samplerGranular, v ? 1 : 0),
              ),
            ],
          ),
          if (track.samplerGranularEnabled) ...[
            const _Caption('読み位置の動き'),
            SegmentChips(
              options: const [(0, '全体を這う'), (1, '曲位置に同期'), (2, '狭いループ'), (3, '往復（ピンポン）')],
              selected: track.samplerGranularPositionMode,
              color: color,
              onSelected: (m) => _granular(MdawParam.samplerGranularPositionMode, m.toDouble()),
            ),
            const SizedBox(height: 8),
            const _Caption('プリセット（選ぶと粒の質感が一式入ります）'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in samplerGranularPresets)
                  ActionChip(
                    label: Text(preset.name, style: const TextStyle(fontSize: 12)),
                    avatar: Icon(Icons.auto_awesome, size: 14, color: color),
                    onPressed: () => _granularPreset(preset),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                for (final key in const ['sizeMs', 'density'])
                  _CommitKnob(
                    label: key == 'sizeMs' ? '粒の大きさ' : '密度',
                    param: _sgParam(key),
                    value: samplerGranularValueOf(track, _sgParam(key).id),
                    color: color,
                    format: _granularFormat,
                    onCommit: (v) => _granular(_sgParam(key).id, v),
                  ),
              ],
            ),
            // 主面の主要パラメータは音楽的な名前で（霧＝質感、広がり＝散らばり）
            for (final (key, label) in const [('texture', '霧（粒の輪郭と溶け具合）'), ('spray', '広がり（位置の散らばり）')])
              _CommitSlider(
                label: label,
                value: samplerGranularValueOf(track, _sgParam(key).id),
                min: _sgParam(key).min,
                max: _sgParam(key).max,
                format: (v) => _granularFormat(_sgParam(key), v),
                onCommit: (v) => _granular(_sgParam(key).id, v),
              ),
            Row(
              children: [
                const Expanded(child: _Caption('細かく調整')),
                Switch(
                  value: _showGranularDetail,
                  activeThumbColor: color,
                  onChanged: (v) => setState(() => _showGranularDetail = v),
                ),
              ],
            ),
            if (_showGranularDetail) ...[
              for (final key in const [
                'position',
                'pitchSpread',
                'timingRandom',
                'sizeRandom',
                'reverseChance',
                'roam',
                'roamSpeed',
                'feedback',
                'pitchDrift',
              ])
                _CommitSlider(
                  label: _sgParam(key).label,
                  value: samplerGranularValueOf(track, _sgParam(key).id),
                  min: _sgParam(key).min,
                  max: _sgParam(key).max,
                  format: (v) => _granularFormat(_sgParam(key), v),
                  onCommit: (v) => _granular(_sgParam(key).id, v),
                ),
              Row(
                children: [
                  const Expanded(child: _Caption('フリーズ（読み位置を凍らせる）')),
                  Switch(
                    value: track.samplerGranularFreeze,
                    activeThumbColor: color,
                    onChanged: (v) => _granular(MdawParam.samplerGranularFreeze, v ? 1 : 0),
                  ),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: _Caption('ピッチ量子化（粒を和音の音程に寄せる）')),
                  Switch(
                    value: track.samplerGranularPitchQuantize,
                    activeThumbColor: color,
                    onChanged: (v) => _granular(MdawParam.samplerGranularPitchQuantize, v ? 1 : 0),
                  ),
                ],
              ),
            ],
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('粒は鍵盤の音程で鳴ります。ノートオフでは雲がゆっくり（0.4秒）消えます',
                  style: TextStyle(fontSize: 11, color: DawColors.muted)),
            ),
          ],
        ],
        if (widget.bounceSection != null) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          widget.bounceSection!,
        ],
      ],
    );
  }
}

/// ドラッグ中は手元で値を保持し、離したときに1回だけ確定するスライダー
/// （サンプラーの設定はコマンド単位で確定するため、シンセの live 経路を使わない）
class _CommitSlider extends StatefulWidget {
  const _CommitSlider(
      {required this.label, required this.value, required this.min, required this.max, required this.format, required this.onCommit});

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final void Function(double) onCommit;

  @override
  State<_CommitSlider> createState() => _CommitSliderState();
}

class _CommitSliderState extends State<_CommitSlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(_CommitSlider old) {
    super.didUpdateWidget(old);
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(width: 76, child: Text(widget.label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: Slider(
              value: _value.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              onChanged: (v) => setState(() => _value = v),
              onChangeEnd: (v) => widget.onCommit(v),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(widget.format(_value),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}

/// _CommitSlider のノブ版：ドラッグ中は手元で保持し、離したときに1回だけ確定する
/// （サンプラーのグラニュラー設定用。SoundParam の unit 変換を使う）
class _CommitKnob extends StatefulWidget {
  const _CommitKnob(
      {required this.label, required this.param, required this.value, required this.color, required this.format, required this.onCommit});

  final String label;
  final SoundParam param;
  final double value;
  final Color color;
  final String Function(SoundParam p, double v) format;
  final void Function(double) onCommit;

  @override
  State<_CommitKnob> createState() => _CommitKnobState();
}

class _CommitKnobState extends State<_CommitKnob> {
  late double _unit = widget.param.toUnit(widget.value);

  @override
  void didUpdateWidget(_CommitKnob old) {
    super.didUpdateWidget(old);
    _unit = widget.param.toUnit(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return ParamKnob(
      label: widget.label,
      valueText: widget.format(widget.param, widget.param.fromUnit(_unit)),
      unit: _unit,
      color: widget.color,
      onChanged: (u) => setState(() => _unit = u),
      onChangeEnd: (_) => widget.onCommit(widget.param.fromUnit(_unit)),
      onReset: () {
        setState(() => _unit = widget.param.toUnit(widget.param.def));
        widget.onCommit(widget.param.def);
      },
    );
  }
}
