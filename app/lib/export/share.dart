// 書き出したファイルを Android の共有シートへ渡す（MainActivity の mobiledaw/share と揃える）
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('mobiledaw/share');

/// 書き出しの置き場所（キャッシュの exports/。res/xml/update_paths.xml と揃える）
Future<String> exportsDir() async {
  final dir = await _channel.invokeMethod<String>('exportsDir');
  if (dir == null) throw StateError('書き出し先を取得できませんでした');
  return dir;
}

/// ファイルを共有シートで開く（Drive に保存・他のアプリに送る など）
Future<void> shareFiles(List<String> paths, {required String mimeType, String? title}) =>
    _channel.invokeMethod<void>('share', {'paths': paths, 'mimeType': mimeType, 'title': title});
