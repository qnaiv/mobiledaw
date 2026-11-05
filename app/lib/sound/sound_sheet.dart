// 音色シート：トラック名タップで出る。楽器（VSTi のように選ぶ）→ プリセット（セレクトボックス）
// → 楽器専用パネル → 大きいつまみ → 必要なら「詳しく」。
// つまみは再生しながら動かせて、離すまでが1回の Undo。
import 'package:flutter/material.dart';

import '../arrange/mixer_sheet.dart';
import '../arrange/song_controller.dart';
import '../engine/mdaw_ffi.dart';
import '../kits/kits_screen.dart';
import '../model/project.dart';
import '../ui/theme.dart';
import 'sound_params.dart';
import 'wave_painters.dart';

Future<void> showSoundSheet(BuildContext context, SongController song, int trackId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DawColors.panel,
    builder: (context) => _SoundSheet(song: song, trackId: trackId),
  );
}

/// 楽器の識別子と見た目（モックアップで決めた色分け）
const _kAnalog = 'analog';
const _kWavetable = 'wt';
const _kKit = 'kit';

const _instNames = {_kAnalog: 'アナログ・シンセ', _kWavetable: 'ウェーブテーブル', _kKit: 'ドラムキット'};
const _instColors = {_kAnalog: Color(0xFFF0A13C), _kWavetable: Color(0xFF35C4B5), _kKit: Color(0xFFE879C6)};

/// トラックが今どの楽器か（キット優先、シンセは wtTable で判定）
String _instrumentOf(TrackData t) {
  if (t.isKit) return _kKit;
  return (t.synth['wtTable'] ?? 0) >= 1 ? _kWavetable : _kAnalog;
}

SoundParam _paramOf(String key) => allSoundParams.firstWhere((p) => p.key == key);

class _SoundSheet extends StatelessWidget {
  const _SoundSheet({required this.song, required this.trackId});

  final SongController song;
  final int trackId;

  void _audition(TrackData track) {
    song.previewTrack(trackId);
    final kit = track.isKit ? song.kits.installed(track.kitId) : null;
    if (kit != null) {
      // キットは最初の数音を順に
      song.auditionSequence([for (final n in kit.notes.take(4)) [n]], each: const Duration(milliseconds: 280));
    } else {
      song.auditionChord(const [60, 63, 67, 70]);
    }
  }

  Future<void> _pickKit(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<String>(builder: (_) => KitsScreen(song: song, pickFor: trackId)));
    song.previewTrack(trackId);
  }

  void _selectInstrument(BuildContext context, TrackData track, String inst) {
    if (inst == _instrumentOf(track)) return;
    if (inst == _kKit) {
      // 入っているキットがあれば最初のもの、無ければ探す画面へ
      final have = song.kits.installedKits();
      if (have.isEmpty) {
        _pickKit(context);
      } else {
        song.setTrackKit(trackId, have.first.id);
        song.previewTrack(trackId);
      }
      return;
    }
    if (track.isKit) song.setTrackKit(trackId, '');
    if (inst == _kAnalog) {
      song.setSound(trackId, MdawParam.wtTable, 0);
    } else if ((track.synth['wtTable'] ?? 0) < 1) {
      song.setSound(trackId, MdawParam.wtTable, 1);
    }
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
            final inst = _instrumentOf(track);
            final instColor = _instColors[inst]!;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
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
                    IconButton(
                        tooltip: '試聴', onPressed: () => _audition(track), icon: const Icon(Icons.play_circle_outline)),
                    IconButton(
                      tooltip: 'ミキサー',
                      onPressed: () => showMixerSheet(context, song, focusTrackId: trackId),
                      icon: const Icon(Icons.tune),
                    ),
                    IconButton(
                      tooltip: '元に戻す',
                      onPressed: song.canUndo ? song.undo : null,
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
                      onTap: () => _selectInstrument(context, track, _kAnalog),
                    ),
                    const SizedBox(width: 8),
                    _InstCard(
                      icon: Icons.waves,
                      name: 'ウェーブテーブル',
                      sub: '波形が変化',
                      color: _instColors[_kWavetable]!,
                      selected: inst == _kWavetable,
                      onTap: () => _selectInstrument(context, track, _kWavetable),
                    ),
                    const SizedBox(width: 8),
                    _InstCard(
                      icon: Icons.grid_view,
                      name: 'ドラムキット',
                      sub: 'パッドで鳴らす',
                      color: _instColors[_kKit]!,
                      selected: inst == _kKit,
                      onTap: () => _selectInstrument(context, track, _kKit),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (inst == _kKit) ...[
                  _KitPanel(song: song, track: track, onBrowse: () => _pickKit(context)),
                  const SizedBox(height: 8),
                  for (final m in soundMacros.where((m) => m.label == 'パンプ')) _MacroSlider(song: song, track: track, macro: m),
                  _DetailSection(title: '詳しく：エフェクト', song: song, track: track, params: fxParams),
                ] else if (inst == _kWavetable) ...[
                  _WavetablePanel(song: song, track: track),
                ] else ...[
                  _AnalogPanel(song: song, track: track),
                ],
              ],
            );
          },
        ),
      ),
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
  const _PresetSelect({required this.song, required this.track, required this.presets});

  final SongController song;
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
              song.setSounds(track.id, p.allValues);
              song.previewTrack(track.id);
              song.auditionChord(p.category == 'ドラム' ? const [48] : const [60, 63, 67, 70]);
            },
          ),
        ),
      ],
    );
  }
}

void _macrosAndSections({
  required List<Widget> into,
  required SongController song,
  required TrackData track,
  required List<(String, List<SoundParam>)> sections,
}) {
  into.add(const _Caption('大きいつまみ'));
  for (final m in soundMacros) {
    into.add(_MacroSlider(song: song, track: track, macro: m));
  }
  into.add(const SizedBox(height: 8));
  for (final (title, params) in sections) {
    into.add(_DetailSection(title: title, song: song, track: track, params: params));
  }
}

/// アナログ・シンセの専用パネル（アンバー：波形・フィルター特性・ADSR が見える）
class _AnalogPanel extends StatelessWidget {
  const _AnalogPanel({required this.song, required this.track});

  final SongController song;
  final TrackData track;

  @override
  Widget build(BuildContext context) {
    final color = _instColors[_kAnalog]!;
    final wave = _paramOf('wave');
    final cutoff = _paramOf('cutoffHz');
    final res = _paramOf('resonance');
    final children = <Widget>[
      _PresetSelect(song: song, track: track, presets: [for (final p in soundPresets) if (!p.isWavetable) p]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(border: Border.all(color: DawColors.line), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ANALOG', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: color)),
            _ParamRow(song: song, track: track, param: wave),
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
      const SizedBox(height: 12),
    ];
    _macrosAndSections(
      into: children,
      song: song,
      track: track,
      sections: [
        ('詳しく：オシレーター', analogOscParams),
        ('詳しく：フィルター', filterParams),
        ('詳しく：エンベロープ', envParams),
        ('詳しく：エフェクト', fxParams),
      ],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// ウェーブテーブル・シンセの専用パネル（ティール：波形モーフが見える）
class _WavetablePanel extends StatelessWidget {
  const _WavetablePanel({required this.song, required this.track});

  final SongController song;
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
    final children = <Widget>[
      _PresetSelect(song: song, track: track, presets: [for (final p in soundPresets) if (p.isWavetable) p]),
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
                dim: DawColors.muted,
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
                    onTap: () => song.setSound(track.id, MdawParam.wtTable, id.toDouble()),
                  ),
              ],
            ),
            _ParamRow(song: song, track: track, param: posParam),
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
                    onTap: () => song.setSound(track.id, MdawParam.wtWarp, id.toDouble()),
                  ),
              ],
            ),
            _ParamRow(song: song, track: track, param: warpAmtParam),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('カスタム波形（WAVを読み込む／波形を描く）は準備中です', style: TextStyle(fontSize: 11, color: DawColors.muted)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
    _macrosAndSections(
      into: children,
      song: song,
      track: track,
      sections: [
        ('詳しく：ユニゾン', unisonParams),
        ('詳しく：フィルター', filterParams),
        ('詳しく：エンベロープ', envParams),
        ('詳しく：エフェクト', fxParams),
      ],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
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
  const _KitPanel({required this.song, required this.track, required this.onBrowse});

  final SongController song;
  final TrackData track;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final kit = song.kits.installed(track.kitId);
    final installed = song.kits.installedKits();
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
                        song.setTrackKit(track.id, id);
                        song.previewTrack(track.id);
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
                    song.previewTrack(track.id);
                    song.audition(snd.note, velocity: 0.9);
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
  const _MacroSlider({required this.song, required this.track, required this.macro});

  final SongController song;
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
                onChangeStart: (_) => song.beginGesture(),
                onChanged: (u) => song.setSounds(track.id, macro.write(u)),
                onChangeEnd: (_) => song.endGesture(),
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

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.song, required this.track, required this.params});

  final String title;
  final SongController song;
  final TrackData track;
  final List<SoundParam> params;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontSize: 14)),
        children: [for (final p in params) _ParamRow(song: song, track: track, param: p)],
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow({required this.song, required this.track, required this.param});

  final SongController song;
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
              onSelectionChanged: (s) => song.setSound(track.id, param.id, s.first ? 1 : 0),
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
              onChangeStart: (_) => song.beginGesture(),
              onChanged: (u) => song.setSound(track.id, param.id, param.fromUnit(u)),
              onChangeEnd: (_) => song.endGesture(),
            ),
          ),
          GestureDetector(
            // ダブルタップで既定値に戻す
            onDoubleTap: () => song.setSound(track.id, param.id, param.def),
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
