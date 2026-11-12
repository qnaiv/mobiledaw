// Windows のファイルダイアログ（windows/runner の mobiledaw/files と揃える）。
// プロジェクトの取り込み／書き出し機能が付くときに使う土台で、Phase 1 では
// まだ画面からは呼んでいない。Windows 以外では何もせず null を返す。
import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('mobiledaw/files');

/// 開くファイルを選ぶ。やめたら null
Future<String?> pickOpenFile({String? title, String? filterName, String? extension}) async {
  if (!Platform.isWindows) return null;
  return _channel.invokeMethod<String>('openFile', {
    'title': title,
    'filterName': filterName,
    'extension': extension,
  });
}

/// 保存先を選ぶ。やめたら null
Future<String?> pickSaveFile({String? title, String? defaultName, String? filterName, String? extension}) async {
  if (!Platform.isWindows) return null;
  return _channel.invokeMethod<String>('saveFile', {
    'title': title,
    'defaultName': defaultName,
    'filterName': filterName,
    'extension': extension,
  });
}
