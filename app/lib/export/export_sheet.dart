// 書き出し：曲をまとめて wav／トラックごとの wav／MIDI。できたら共有シートへ。
// wav はコアが別スレッドで計算する（リアルタイムより速い）。ここでは進み具合を見て待つだけ。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../engine/mdaw_ffi.dart';
import '../project/library.dart';
import '../ui/theme.dart';
import 'midi.dart';
import 'share.dart';

enum ExportKind { mix, stems, midi }

Future<void> showExportSheet(BuildContext context, SongController song) async {
  final kind = await showModalBottomSheet<ExportKind>(
    context: context,
    backgroundColor: DawColors.panel,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('書き出し', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: const Text('曲をまとめて（WAV）'),
            subtitle: const Text('48kHz・24bit。アプリで聴いた音そのまま'),
            onTap: () => Navigator.pop(context, ExportKind.mix),
          ),
          ListTile(
            leading: const Icon(Icons.view_week_outlined),
            title: const Text('トラックごと（WAV）'),
            subtitle: const Text('トラック1本ずつ。ミックスし直したいとき用（仕上げのリミッターなし）'),
            onTap: () => Navigator.pop(context, ExportKind.stems),
          ),
          ListTile(
            leading: const Icon(Icons.piano_outlined),
            title: const Text('MIDI'),
            subtitle: const Text('ノートだけ。パソコンの DAW で続きを作るとき用'),
            onTap: () => Navigator.pop(context, ExportKind.midi),
          ),
        ],
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  await runExport(context, song, kind);
}

Future<void> runExport(BuildContext context, SongController song, ExportKind kind) async {
  final messenger = ScaffoldMessenger.of(context);
  final project = song.project;
  if (project.placements.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('曲が空です。クリップを置いてから書き出してください')));
    return;
  }
  song.saveNow();
  final dir = await exportsDir();
  // 前回の書き出しは消しておく（キャッシュなので溜めない）
  for (final f in Directory(dir).listSync().whereType<File>()) {
    try {
      f.deleteSync();
    } on Object {
      // 使用中なら残す
    }
  }
  final base = safeFileName(project.title);

  if (kind == ExportKind.midi) {
    final path = '$dir/$base.mid';
    File(path).writeAsBytesSync(buildMidi(project));
    await shareFiles([path], mimeType: 'audio/midi', title: project.title);
    return;
  }

  final jobs = kind == ExportKind.mix
      ? [_Job(0, '$dir/$base.wav', project.title)]
      : [
          for (var i = 0; i < project.tracks.length; i++)
            _Job(project.tracks[i].id, '$dir/$base - ${(i + 1).toString().padLeft(2, '0')} ${safeFileName(project.tracks[i].name)}.wav',
                project.tracks[i].name),
        ];
  song.engine.stopPlayback();
  if (!context.mounted) return;
  final result = await showDialog<_Result>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ExportDialog(engine: song.engine, jobs: jobs),
  );
  if (result == null) return;
  if (result.error != null) {
    messenger.showSnackBar(SnackBar(content: Text('書き出せませんでした：${result.error}')));
    return;
  }
  if (result.paths.isEmpty) return; // やめた
  await shareFiles(result.paths, mimeType: 'audio/wav', title: project.title);
}

class _Job {
  const _Job(this.trackId, this.path, this.label);
  final int trackId;
  final String path;
  final String label;
}

class _Result {
  const _Result(this.paths, [this.error]);
  final List<String> paths;
  final String? error;
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.engine, required this.jobs});

  final MdawEngine engine;
  final List<_Job> jobs;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  int _index = 0;
  double _progress = 0;
  bool _cancelled = false;
  Timer? _timer;
  final _done = <String>[];

  @override
  void initState() {
    super.initState();
    _startJob();
  }

  void _startJob() {
    final job = widget.jobs[_index];
    if (!widget.engine.exportStart(job.path, trackId: job.trackId)) {
      _finish(const _Result([], '書き出しを始められませんでした'));
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _poll());
  }

  void _poll() {
    final e = widget.engine;
    switch (e.exportState) {
      case ExportState.running:
      case ExportState.idle:
        setState(() => _progress = e.exportProgress);
      case ExportState.done:
        _timer?.cancel();
        _done.add(widget.jobs[_index].path);
        if (_index + 1 < widget.jobs.length && !_cancelled) {
          setState(() {
            _index++;
            _progress = 0;
          });
          _startJob();
        } else {
          _finish(_Result(_cancelled ? const [] : List.of(_done)));
        }
      case ExportState.cancelled:
        _timer?.cancel();
        _finish(const _Result([]));
      case ExportState.failed:
        _timer?.cancel();
        _finish(_Result(const [], e.exportError));
    }
  }

  void _finish(_Result r) {
    if (mounted) Navigator.of(context).pop(r);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.jobs.length;
    final overall = (_index + _progress) / n;
    final job = widget.jobs[_index];
    return AlertDialog(
      title: const Text('書き出し中'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n > 1 ? '${_index + 1} / $n  ${job.label}' : job.label,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: overall),
          const SizedBox(height: 6),
          Text('${(overall * 100).round()}%', style: const TextStyle(color: DawColors.muted, fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _cancelled
              ? null
              : () {
                  setState(() => _cancelled = true);
                  widget.engine.exportCancel();
                },
          child: const Text('やめる'),
        ),
      ],
    );
  }
}
