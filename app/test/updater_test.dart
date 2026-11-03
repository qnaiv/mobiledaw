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

  test('ignores releases that are not app builds', () {
    expect(UpdateInfo.fromRelease({'tag_name': 'v1.0', 'assets': <Object?>[]}), isNull);
    expect(UpdateInfo.fromRelease({'tag_name': 'build-3', 'assets': <Object?>[]}), isNull);
    expect(UpdateInfo.fromRelease(<String, Object?>{}), isNull);
  });
}
