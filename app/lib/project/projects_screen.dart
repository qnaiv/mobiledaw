// 曲の一覧：開く・新しい曲・複製・名前を変える・削除・書き出し／取り込み。
// 新しく保存した順に並ぶ。
import 'dart:io';

import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../export/share.dart';
import '../showcase/showcase_screen.dart';
import '../kits/kit_gate.dart';
import '../platform_files.dart';
import '../ui/theme.dart';
import '../update/updater.dart';
import 'library.dart';
import 'project_transfer.dart';

/// 曲名を入れてもらう（空ならやめる）
Future<String?> askSongTitle(BuildContext context, {required String title, String initial = '', String ok = '決める'}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(hintText: '曲の名前'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('やめる')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(ok)),
      ],
    ),
  );
  controller.dispose();
  final t = name?.trim();
  return t == null || t.isEmpty ? null : t;
}

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.song});

  final SongController song;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  SongController get song => widget.song;
  ProjectLibrary get library => song.library;
  late List<ProjectEntry> _entries;

  @override
  void initState() {
    super.initState();
    song.saveNow(); // 開いている曲の名前・更新時刻を一覧に反映
    _entries = library.list();
  }

  void _reload() => setState(() => _entries = library.list());

  String _when(DateTime t) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(t.hour)}:${two(t.minute)}';
    if (now.year == t.year && now.month == t.month && now.day == t.day) return '今日 $hm';
    return '${t.year}/${two(t.month)}/${two(t.day)} $hm';
  }

  /// 開く。使っているキットが足りなければ、ダウンロードするまで開かない
  Future<void> _open(ProjectEntry e) async {
    if (e.id != song.projectId && !await ensureKits(context, song, kitsInProjectFile(e.path))) return;
    if (!mounted) return;
    song.openProject(e.id);
    Navigator.pop(context);
  }

  Future<void> _new() async {
    final title = await askSongTitle(context, title: '新しい曲', initial: '無題の曲', ok: '作る');
    if (title == null || !mounted) return;
    song.newSong(title: title);
    Navigator.pop(context);
  }

  Future<void> _rename(ProjectEntry e) async {
    final title = await askSongTitle(context, title: '名前を変える', initial: e.title);
    if (title == null) return;
    if (e.id == song.projectId) {
      song.renameSong(title);
      song.saveNow();
    } else {
      library.rename(e.id, title);
    }
    _reload();
  }

  /// ショーケース再生：その曲を開いてから、再生専用画面へ。
  /// 再生中の曲なら再生は止めず、レインが現在位置から続く
  Future<void> _showcase(ProjectEntry e) async {
    if (e.id != song.projectId) {
      if (!await ensureKits(context, song, kitsInProjectFile(e.path))) return;
      if (!mounted) return;
      song.openProject(e.id);
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShowcaseScreen(song: song)));
  }

  void _duplicate(ProjectEntry e) {
    if (e.id == song.projectId) song.saveNow();
    library.duplicate(e.id);
    _reload();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// プロジェクトを .mdawproj ファイルに書き出す。
  /// Windows は保存ダイアログ、Android は共有シート（WAV/MIDI 書き出しと同じ経路）。
  Future<void> _export(ProjectEntry e) async {
    if (e.id == song.projectId) song.saveNow();
    try {
      if (Platform.isWindows) {
        final path = await pickSaveFile(
          title: 'プロジェクトを書き出す',
          defaultName: '${safeFileName(e.title)}.$projectFileExtension',
          filterName: 'プロジェクトファイル',
          extension: projectFileExtension,
        );
        if (path == null) return;
        final target = File(path.endsWith('.$projectFileExtension') ? path : '$path.$projectFileExtension');
        await writeProjectFile(library: library, id: e.id, target: target, appBuild: currentBuild);
        _toast('書き出しました：${target.path}');
      } else {
        final dir = await exportsDir();
        final target = File('$dir/${safeFileName(e.title)}.$projectFileExtension');
        await writeProjectFile(library: library, id: e.id, target: target, appBuild: currentBuild);
        await shareFiles([target.path], mimeType: 'application/zip', title: e.title);
      }
    } on ProjectTransferException catch (err) {
      _toast(err.message);
    } on Object {
      _toast('書き出しに失敗しました');
    }
  }

  /// .mdawproj ファイルを取り込んで、新しい曲として一覧に足す
  Future<void> _import() async {
    final path = await pickOpenFile(
      title: 'プロジェクトを取り込む',
      filterName: 'プロジェクトファイル',
      extension: projectFileExtension,
    );
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      final entry = importProjectArchive(library, bytes);
      _reload();
      _toast('「${entry.title}」を取り込みました');
    } on ProjectTransferException catch (err) {
      _toast(err.message);
    } on Object {
      _toast('取り込みに失敗しました');
    }
  }

  Future<void> _delete(ProjectEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('「${e.title}」を削除しますか？'),
        content: const Text('削除した曲は元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DawColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final wasOpen = e.id == song.projectId;
    library.delete(e.id);
    if (wasOpen) {
      // 開いていた曲を消したら、残っている一番新しい曲か新しい曲を開く
      final rest = [for (final r in library.list()) if (missingKits(song.kits, kitsInProjectFile(r.path)).isEmpty) r];
      if (rest.isEmpty) {
        song.newSong();
      } else {
        song.openProject(rest.first.id);
      }
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final current = song.projectId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('曲の一覧'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'プロジェクトを取り込む',
            onPressed: _import,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('新しい曲'),
      ),
      body: _entries.isEmpty
          ? const Center(child: Text('まだ曲がありません', style: TextStyle(color: DawColors.muted)))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: _entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final e = _entries[i];
                final isOpen = e.id == current;
                return Material(
                  color: DawColors.panel,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isOpen ? DawColors.accent : DawColors.line),
                    ),
                    leading: Icon(isOpen ? Icons.music_note : Icons.music_note_outlined,
                        color: isOpen ? DawColors.accent : DawColors.muted),
                    title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(isOpen ? '開いている曲 · ${_when(e.updated)}' : _when(e.updated),
                        style: const TextStyle(fontSize: 12, color: DawColors.muted)),
                    onTap: () => _open(e),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        switch (v) {
                          case 'rename':
                            _rename(e);
                          case 'showcase':
                            _showcase(e);
                          case 'duplicate':
                            _duplicate(e);
                          case 'export':
                            _export(e);
                          case 'delete':
                            _delete(e);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('名前を変える')),
                        PopupMenuItem(value: 'showcase', child: Text('ショーケース再生')),
                        PopupMenuItem(value: 'duplicate', child: Text('複製')),
                        PopupMenuItem(value: 'export', child: Text('プロジェクトを書き出す')),
                        PopupMenuItem(value: 'delete', child: Text('削除')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
