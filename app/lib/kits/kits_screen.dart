// キットを探す：GitHub にあるキットの一覧から、ダウンロード・更新・削除する。
// [pickFor] を渡すと、ダウンロード済みのキットをタップでそのトラックに使う。
import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../ui/theme.dart';
import 'kit_store.dart';

class KitsScreen extends StatefulWidget {
  const KitsScreen({super.key, required this.song, this.pickFor});

  final SongController song;
  final int? pickFor; // トラックの ID

  @override
  State<KitsScreen> createState() => _KitsScreenState();
}

class _KitsScreenState extends State<KitsScreen> {
  KitStore get store => widget.song.kits;
  List<RemoteKit> _remote = const [];
  String? _error;
  bool _loading = true;
  final _progress = <String, double>{}; // ダウンロード中のキット

  @override
  void initState() {
    super.initState();
    _remote = store.cachedRemote();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await store.fetchRemote();
      if (mounted) setState(() => _remote = r);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'キットの一覧を取れませんでした（オフライン？）：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(RemoteKit kit) async {
    setState(() => _progress[kit.id] = 0);
    try {
      await store.download(kit, onProgress: (p) {
        if (mounted) setState(() => _progress[kit.id] = p);
      });
      widget.song.kitsChanged();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「${kit.name}」をダウンロードできませんでした：$e')));
      }
    } finally {
      if (mounted) setState(() => _progress.remove(kit.id));
    }
  }

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('「$name」を削除しますか？'),
        content: const Text('このキットを使っているトラックは、ダウンロードし直すまで鳴らなくなります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    store.delete(id);
    widget.song.kitsChanged();
    setState(() {});
  }

  void _use(String id) {
    final t = widget.pickFor;
    if (t == null) return;
    widget.song.setTrackKit(t, id);
    Navigator.pop(context, id);
  }

  String _size(int bytes) => bytes >= 1000000 ? '${(bytes / 1000000).toStringAsFixed(1)} MB' : '${(bytes / 1000).round()} KB';

  @override
  Widget build(BuildContext context) {
    // 一覧にあるもの＋（一覧から消えたが）ダウンロード済みのもの
    final installed = {for (final k in store.installedKits()) k.id: k};
    final ids = {for (final k in _remote) k.id, ...installed.keys};
    final remoteById = {for (final k in _remote) k.id: k};
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickFor == null ? 'ドラムキット' : 'キットを選ぶ'),
        actions: [
          IconButton(tooltip: '一覧を読み直す', onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: const TextStyle(color: DawColors.danger, fontSize: 12)),
              ),
            if (widget.pickFor != null)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text('ダウンロード済みのキットをタップすると、そのトラックで使います',
                    style: TextStyle(fontSize: 12, color: DawColors.muted)),
              ),
            for (final id in ids)
              _KitTile(
                remote: remoteById[id],
                installed: installed[id],
                progress: _progress[id],
                size: _size,
                onDownload: remoteById[id] == null ? null : () => _download(remoteById[id]!),
                onDelete: installed[id] == null ? null : () => _delete(id, installed[id]!.name),
                onUse: widget.pickFor != null && installed[id] != null ? () => _use(id) : null,
              ),
            if (ids.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('キットがありません', style: TextStyle(color: DawColors.muted))),
              ),
          ],
        ),
      ),
    );
  }
}

class _KitTile extends StatelessWidget {
  const _KitTile({
    required this.remote,
    required this.installed,
    required this.progress,
    required this.size,
    required this.onDownload,
    required this.onDelete,
    required this.onUse,
  });

  final RemoteKit? remote;
  final InstalledKit? installed;
  final double? progress;
  final String Function(int) size;
  final VoidCallback? onDownload, onDelete, onUse;

  @override
  Widget build(BuildContext context) {
    final name = remote?.name ?? installed!.name;
    final hasUpdate = remote != null && installed != null && remote!.version > installed!.version;
    final details = [
      if (remote != null) '${remote!.sounds}音 · ${size(remote!.size)}' else '${installed!.sounds.length}音',
      if (remote != null && remote!.license.isNotEmpty) remote!.license,
    ].join(' · ');
    Widget action;
    if (progress != null) {
      action = SizedBox(width: 28, height: 28, child: CircularProgressIndicator(value: progress! > 0 ? progress : null, strokeWidth: 3));
    } else if (installed == null) {
      action = FilledButton.tonalIcon(onPressed: onDownload, icon: const Icon(Icons.download, size: 18), label: const Text('入れる'));
    } else {
      action = Row(mainAxisSize: MainAxisSize.min, children: [
        if (hasUpdate) TextButton(onPressed: onDownload, child: const Text('更新')),
        IconButton(tooltip: '削除', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
      ]);
    }
    return Card(
      color: DawColors.panel,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onUse,
        leading: Icon(installed != null ? Icons.check_circle : Icons.cloud_outlined,
            color: installed != null ? DawColors.accent : DawColors.muted),
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (remote != null && remote!.description.isNotEmpty) Text(remote!.description, style: const TextStyle(fontSize: 12)),
            Text(details, style: const TextStyle(fontSize: 11, color: DawColors.muted)),
          ],
        ),
        isThreeLine: remote != null && remote!.description.isNotEmpty,
        trailing: action,
      ),
    );
  }
}
