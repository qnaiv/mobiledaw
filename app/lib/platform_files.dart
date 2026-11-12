// ファイルダイアログ（Windows は windows/runner、Android は MainActivity の
// mobiledaw/files と揃える）。プロジェクトの取り込み／書き出しで使う。
// 対応していない環境では何もせず null を返す。
import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('mobiledaw/files');

bool get _supported => Platform.isWindows || Platform.isAndroid;

/// 開くファイルを選ぶ。やめたら（または未対応なら）null
Future<String?> pickOpenFile({String? title, String? filterName, String? extension}) async {
  if (!_supported) return null;
  try {
    return await _channel.invokeMethod<String>('openFile', {
      'title': title,
      'filterName': filterName,
      'extension': extension,
    });
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// 保存先を選ぶ。やめたら（または未対応なら）null。
/// Android には保存ダイアログの実装が無いため null（書き出しは共有シート経路を使う）。
Future<String?> pickSaveFile({String? title, String? defaultName, String? filterName, String? extension}) async {
  if (!_supported) return null;
  try {
    return await _channel.invokeMethod<String>('saveFile', {
      'title': title,
      'defaultName': defaultName,
      'filterName': filterName,
      'extension': extension,
    });
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
