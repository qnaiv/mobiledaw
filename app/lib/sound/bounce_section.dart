// バウンス素材の作成（Phase 2.5）: 選んだトラックをソロで書き出し（コアの
// トラック単体レンダー）、キットとして登録して、このトラックのサンプラー素材に
// する。素材の参照は通常のサンプラーと同じ（kitId + 音の名前）でプロジェクトに残る。
// 書き出したキットは端末のキット置き場に残るので、プロジェクトを開き直しても鳴る。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../engine/mdaw_ffi.dart';
import '../model/project.dart';
import '../ui/theme.dart';

class BounceSection extends StatefulWidget {
  const BounceSection({super.key, required this.song, required this.track});

  final SongController song;

  /// サンプラーとして編集中のトラック（バウンス素材の受け先）
  final TrackData track;

  @override
  State<BounceSection> createState() => _BounceSectionState();
}

class _BounceSectionState extends State<BounceSection> {
  int? _sourceId;
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

  List<TrackData> get _tracks => widget.song.project.tracks;

  int get _source => _sourceId ?? (_tracks.firstWhere((t) => t.id != widget.track.id, orElse: () => widget.track).id);

  /// キット ID は [a-z0-9-] のみ・48 字以内（コアの isValidKitId に合わせる）
  String _newKitId() {
    var base = (widget.song.projectId ?? 'project')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.isEmpty) base = 'project';
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    var id = 'bounce-$base-$stamp';
    if (id.length > 48) id = id.substring(0, 48).replaceAll(RegExp(r'-+$'), '');
    return id;
  }

  Future<void> _start() async {
    final song = widget.song;
    final source = _tracks.firstWhere((t) => t.id == _source, orElse: () => widget.track);
    final kitId = _newKitId();
    final soundName = source.name.isEmpty ? 'フレーズ' : source.name;
    final dir = Directory('${song.kits.root.path}/$kitId');
    final wavPath = '${dir.path}/phrase.wav';
    setState(() {
      _busy = true;
      _progress = 0;
      _status = null;
      _failed = false;
    });
    if (!song.engine.exportStart(wavPath, trackId: source.id)) {
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

  Future<void> _finish(String kitId, String soundName, Directory dir) async {
    final song = widget.song;
    try {
      // 書き出し WAV をそのまま素材にするキットを登録する
      await File('${dir.path}/kit.json').writeAsString(jsonEncode({
        'name': 'バウンス素材',
        'version': 1,
        'sounds': [
          {'name': soundName, 'file': 'phrase.wav', 'note': 60, 'gain': 1.0},
        ],
      }));
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
    song.setTrackSampler(widget.track.id, kitId, soundName, 60, 1.0, 0.0);
    song.setTrackSamplerParam(widget.track.id, MdawParam.samplerGranular, 1);
    song.previewTrack(widget.track.id);
    if (mounted) {
      setState(() {
        _busy = false;
        _status = '「$soundName」を素材にしてグラニュラーを ON にしました';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('バウンス素材を作る', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DawColors.muted)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: _tracks.any((t) => t.id == _source) ? _source : null,
                hint: const Text('トラックがありません'),
                items: [
                  for (final t in _tracks) DropdownMenuItem(value: t.id, child: Text(t.name.isEmpty ? '（無題）' : t.name)),
                ],
                onChanged: _busy ? null : (id) => setState(() => _sourceId = id),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _busy || _tracks.isEmpty ? null : _start,
              child: Text(_busy ? '書き出し中…' : '書き出して素材にする'),
            ),
          ],
        ),
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
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('選んだトラックだけを書き出し、このトラックの素材にします（グラニュラーも ON になります）。'
              '素材は 30 秒を超えると読み込み時に切れます',
              style: TextStyle(fontSize: 11, color: DawColors.muted)),
        ),
      ],
    );
  }
}
