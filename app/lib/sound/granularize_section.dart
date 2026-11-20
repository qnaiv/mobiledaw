// グラニュラー化（Phase 2.6）: 素材化したいトラック自身の音色画面から実行する。
// このトラックを書き出してキット素材にし、
//  - 置き換え: このトラック自身がサンプラー＋グラニュラーになる（元の音色は
//    「元に戻す」で戻せる。元のフレーズが裏で鳴り続けることはない）
//  - 重ねる  : 新しいトラックを作ってそちらをグラニュラーにする（元は鳴ったまま）
// 範囲は配置単位で部分指定もできる。書き出し・切り出しは bounce_core を共有。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../engine/mdaw_ffi.dart';
import '../model/project.dart';
import '../ui/theme.dart';
import 'bounce_core.dart';
import 'sound_params.dart';

class GranularizeSection extends StatefulWidget {
  const GranularizeSection({super.key, required this.song, required this.track});

  final SongController song;

  /// 素材化したいトラック（音色編集中のトラック自身）
  final TrackData track;

  @override
  State<GranularizeSection> createState() => _GranularizeSectionState();
}

class _GranularizeSectionState extends State<GranularizeSection> {
  bool _open = false;
  bool _partial = false;
  int? _rangeStartId;
  int? _rangeEndId;
  bool _replace = true;
  bool _busy = false;
  double _progress = 0;
  String? _status;
  bool _failed = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<PlacementData> get _placements => placementsOf(widget.song.project, widget.track.id);

  ({int startBar, int endBar})? get _range {
    if (!_partial) return null;
    final ps = _placements;
    if (ps.isEmpty) return null;
    final start = ps.firstWhere((p) => p.id == _rangeStartId, orElse: () => ps.first);
    final end = ps.firstWhere((p) => p.id == _rangeEndId, orElse: () => ps.last);
    if (end.endBar <= start.startBar) return null;
    return (startBar: start.startBar, endBar: end.endBar);
  }

  Future<void> _start() async {
    final song = widget.song;
    final source = widget.track;
    final kitId = newBounceKitId(song.projectId);
    final soundName = source.name.isEmpty ? 'フレーズ' : source.name;
    final dir = Directory('${song.kits.root.path}/$kitId');
    setState(() {
      _busy = true;
      _progress = 0;
      _status = null;
      _failed = false;
    });
    if (!song.engine.exportStart('${dir.path}/phrase.wav', trackId: source.id)) {
      setState(() {
        _busy = false;
        _failed = true;
        _status = '書き出しを始められませんでした（別の書き出し中かもしれません）';
      });
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _poll(kitId, soundName, dir));
  }

  Future<void> _poll(String kitId, String soundName, Directory dir) async {
    final engine = widget.song.engine;
    switch (engine.exportState) {
      case ExportState.running:
      case ExportState.idle:
        if (mounted) setState(() => _progress = engine.exportProgress);
      case ExportState.done:
        _timer?.cancel();
        await _finish(kitId, soundName, dir);
      case ExportState.failed:
        _timer?.cancel();
        if (mounted) {
          setState(() {
            _busy = false;
            _failed = true;
            _status = engine.exportError.isEmpty ? '書き出しに失敗しました' : engine.exportError;
          });
        }
      case ExportState.cancelled:
        _timer?.cancel();
        if (mounted) setState(() => _busy = false);
    }
  }

  /// 受け先トラックに素材＋グラニュラー（アンビエント・クラウド）を設定する
  void _applyGranular(int trackId, String kitId, String soundName) {
    final song = widget.song;
    song.setTrackSampler(trackId, kitId, soundName, 60, 1.0, 0.0);
    for (final e in samplerGranularPresets.first.values.entries) {
      song.setTrackSamplerParam(trackId, e.key, e.value);
    }
    song.setTrackSamplerParam(trackId, MdawParam.samplerGranular, 1);
  }

  Future<void> _finish(String kitId, String soundName, Directory dir) async {
    final song = widget.song;
    final range = _range;
    try {
      if (range != null) {
        final ok = await trimWavFileToBars(
            File('${dir.path}/phrase.wav'), song.project, range.startBar, range.endBar);
        if (!ok) throw StateError('trim failed');
      }
      await writeBounceKitJson(dir, soundName);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
          _status = '素材の登録に失敗しました';
        });
      }
      return;
    }
    song.kitsChanged(); // コアにキットを読み直してもらう
    final rangeText = range != null ? '（${range.startBar + 1}〜${range.endBar}小節だけ）' : '';
    if (_replace) {
      _applyGranular(widget.track.id, kitId, soundName);
      song.previewTrack(widget.track.id);
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'このトラックをグラニュラー化しました$rangeText';
        });
      }
    } else {
      // 重ねる: 新しいトラックを作ってそちらを受け先にする（元は鳴ったまま）
      final before = {for (final t in song.project.tracks) t.id};
      song.addTrack();
      final created = song.project.tracks.where((t) => !before.contains(t.id)).toList();
      if (created.isEmpty) {
        if (mounted) {
          setState(() {
            _busy = false;
            _failed = true;
            _status = 'トラックを追加できませんでした（上限の可能性があります）';
          });
        }
        return;
      }
      _applyGranular(created.first.id, kitId, soundName);
      song.previewTrack(created.first.id);
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '新しいトラック「${created.first.name}」をグラニュラーにしました$rangeText';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = _placements;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('グラニュラー化（このトラックを粒で鳴らす）',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DawColors.muted)),
            ),
            FilledButton.tonal(
              onPressed: _busy ? null : () => setState(() => _open = !_open),
              child: Text(_open ? '閉じる' : 'グラニュラー化する'),
            ),
          ],
        ),
        if (_open) ...[
          const SizedBox(height: 6),
          if (ps.isNotEmpty) ...[
            Row(
              children: [
                const Text('範囲', style: TextStyle(fontSize: 12, color: DawColors.muted)),
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('全体')),
                    ButtonSegment(value: true, label: Text('部分（配置）')),
                  ],
                  selected: {_partial},
                  onSelectionChanged: _busy ? null : (s) => setState(() => _partial = s.first),
                ),
              ],
            ),
            if (_partial) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('開始', style: TextStyle(fontSize: 12, color: DawColors.muted)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: ps.any((p) => p.id == _rangeStartId) ? _rangeStartId : ps.first.id,
                      items: [for (final p in ps) DropdownMenuItem(value: p.id, child: Text(placementLabel(p)))],
                      onChanged: _busy ? null : (id) => setState(() => _rangeStartId = id),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('終了', style: TextStyle(fontSize: 12, color: DawColors.muted)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: ps.any((p) => p.id == _rangeEndId) ? _rangeEndId : ps.last.id,
                      items: [for (final p in ps) DropdownMenuItem(value: p.id, child: Text(placementLabel(p)))],
                      onChanged: _busy ? null : (id) => setState(() => _rangeEndId = id),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              const Text('方式', style: TextStyle(fontSize: 12, color: DawColors.muted)),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('置き換える')),
                  ButtonSegment(value: false, label: Text('重ねる')),
                ],
                selected: {_replace},
                onSelectionChanged: _busy ? null : (s) => setState(() => _replace = s.first),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _busy || (_partial && _range == null) ? null : _start,
            child: Text(_busy ? '書き出し中…' : '書き出してグラニュラー化'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('置き換えると、このトラックの音色がサンプラー（グラニュラー）に切り替わり、'
                '元のフレーズが裏で鳴り続けることはありません（「元に戻す」で戻せます）。'
                '重ねる場合は新しいトラックを作ります。素材は 30 秒を超えると読み込み時に切れます',
                style: TextStyle(fontSize: 11, color: DawColors.muted)),
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        ],
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_status!,
                style: TextStyle(fontSize: 12, color: _failed ? DawColors.danger : DawColors.muted)),
          ),
      ],
    );
  }
}
