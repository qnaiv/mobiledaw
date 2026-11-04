// 曲を開く前に、その曲で使っているドラムキットがそろっているかを確かめる。
// 足りなければ「ダウンロードするまで開けません」と聞き、入れ終わってから開く。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../arrange/demo_song.dart';
import '../arrange/song_controller.dart';
import 'kit_store.dart';

/// project.json の中で使っているキットの ID
List<String> kitsInProjectJson(String json) {
  try {
    final j = jsonDecode(json);
    if (j is! Map<String, Object?> || j['tracks'] is! List<Object?>) return const [];
    final ids = <String>{};
    for (final t in j['tracks']! as List<Object?>) {
      if (t is! Map<String, Object?>) continue;
      final inst = t['instrument'];
      if (inst is Map<String, Object?> && inst['type'] == 'kit' && inst['kit'] is String) ids.add(inst['kit']! as String);
    }
    return ids.toList();
  } on Object {
    return const [];
  }
}

List<String> kitsInProjectFile(String path) {
  try {
    return kitsInProjectJson(File(path).readAsStringSync());
  } on Object {
    return const [];
  }
}

Future<List<String>> kitsInDemo(DemoSong demo) async =>
    kitsInProjectJson(await rootBundle.loadString(demoAsset(demo)));

/// まだ入っていないキット
List<String> missingKits(KitStore store, Iterable<String> ids) => [for (final id in ids) if (store.installed(id) == null) id];

/// キットがそろっていれば true。足りなければ聞いて、ダウンロードできたら true、やめた・失敗したら false
Future<bool> ensureKits(BuildContext context, SongController song, Iterable<String> kitIds) async {
  final missing = missingKits(song.kits, kitIds);
  if (missing.isEmpty) return true;
  final known = {for (final k in song.kits.cachedRemote()) k.id: k};
  final names = [for (final id in missing) known[id]?.name ?? id].join('・');
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('キットが必要です'),
      content: Text('プロジェクト内で使用されているキットがないため、ダウンロードするまで開けません。ダウンロードしますか？\n\n$names'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('やめる')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ダウンロード')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final error = await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _DownloadDialog(store: song.kits, ids: missing),
  );
  song.kitsChanged();
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
  return error == null && missingKits(song.kits, kitIds).isEmpty;
}

class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.store, required this.ids});

  final KitStore store;
  final List<String> ids;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  String _label = '一覧を取得しています…';
  double? _progress;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    String? error;
    try {
      final remote = {for (final k in await widget.store.fetchRemote()) k.id: k};
      for (var i = 0; i < widget.ids.length; i++) {
        final kit = remote[widget.ids[i]];
        if (kit == null) throw StateError('キット「${widget.ids[i]}」が見つかりません');
        if (mounted) setState(() => _label = '${kit.name}（${i + 1} / ${widget.ids.length}）');
        await widget.store.download(kit, onProgress: (p) {
          if (mounted) setState(() => _progress = (i + p) / widget.ids.length);
        });
      }
    } on Object catch (e) {
      error = 'キットをダウンロードできませんでした：$e';
    }
    if (mounted) Navigator.of(context).pop(error);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('キットをダウンロード中'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_label),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress),
        ],
      ),
    );
  }
}
