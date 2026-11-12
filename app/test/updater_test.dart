import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/update/updater.dart';

void main() {
  test('reads build number and apk url from the latest release', () {
    final info = UpdateInfo.fromRelease({
      'tag_name': 'build-42',
      'body': 'M2: 縦タイムライン画面\n\n詳しい説明',
      'assets': [
        {'name': 'other.txt', 'browser_download_url': 'https://example.com/other.txt', 'size': 1},
        {
          'name': 'mobiledaw.apk',
          'browser_download_url': 'https://github.com/qnaiv/mobiledaw/releases/download/build-42/mobiledaw.apk',
          'size': 31000000,
        },
      ],
    })!;
    expect(info.build, 42);
    expect(info.apkUrl, endsWith('/build-42/mobiledaw.apk'));
    expect(info.notes.split('\n').first, 'M2: 縦タイムライン画面');
    expect(info.size, 31000000);
  });

  // アップデート（APK のインストール）は Android だけ。Windows などでは
  // リリースに mobiledaw.apk があっても check() が null を返すことを守る
  test('check is disabled off Android', () async {
    if (Platform.isAndroid) return; // Android 上では従来どおり API を見に行く
    expect(await Updater().check(), isNull);
  });

  test('ignores releases that are not app builds', () {
    expect(UpdateInfo.fromRelease({'tag_name': 'v1.0', 'assets': <Object?>[]}), isNull);
    expect(UpdateInfo.fromRelease({'tag_name': 'build-3', 'assets': <Object?>[]}), isNull);
    expect(UpdateInfo.fromRelease(<String, Object?>{}), isNull);
  });
}
