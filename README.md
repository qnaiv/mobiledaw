# mobiledaw

縦持ちのまま使える、自分用のモバイルDAW（Android）。

- 画面案: https://claude.ai/artifact/KBg6bGsWF18Lb1tJDdkSxN
- 設計書: https://claude.ai/artifact/NG7rEPVWfMuyEn4dNzQtyT

## 構成

```
core/      C++ エンジン（libmdaw.so）。音の生成・シーケンス・データモデル
  include/mdaw.h   Flutter（dart:ffi）から呼ぶ C API
  src/             エンジン本体、シンセ、Oboe 出力
  tests/           PC 上で動くテスト
app/       Flutter アプリ（UI）
scripts/   開発用スクリプト
```

- 音声出力は [Oboe](https://github.com/google/oboe)、DSP 部品は [JUCE](https://github.com/juce-framework/JUCE) 9 のモジュール（juce_core / juce_audio_basics / juce_audio_formats / juce_dsp）。どちらも CMake の FetchContent で取得する。
- UI スレッドから音声スレッドへの指示はロックフリーキュー経由。音声スレッドではメモリ確保・ロックをしない。

## 現在地：M2（曲が組める）

`app/` は縦タイムライン（アレンジ）画面から始まる。トラックと小節のマスにクリップを置き、複製・移動・削除、再生（ループ）、Undo/Redo ができる。曲は編集後2秒とアプリが裏に回ったときに自動で保存し、次に開いたときに読み込む。ノートを置く縦ピアノロールは次の作業なので、確かめ用にメニューの「デモ曲を入れる」がある。M1 の「音出しテスト」画面もメニューから開ける。

コアには M2 の土台が入っている：データモデルと編集コマンド・Undo、`project.json` の保存・読み込み、再生用スナップショットとシーケンサー（トラックごとのシンセ、ループ再生）。画面とつなぐ C API は次の作業。

### 再生の仕組み（core/src/playback.*・engine.*）

- コアスレッドが編集のたびに `buildSnapshot(project)` で不変の再生用データを作り、`Engine::publish()` で渡す。クリップと配置は曲頭からの絶対 tick のノートオン／オフ列に展開済み
- 音声スレッドはバッファの頭で一度だけ新しいスナップショットに差し替える。古いものは返却キューで戻し、解放はコアスレッドが行う（音声スレッドでは確保も解放もしない）
- イベントの位置でバッファを区切るので、ノートはサンプル単位で正確に鳴る
- 再生中にノートを消すと、鳴りっぱなしにならないようその場で離す
- 再生・停止・位置移動は SPSC キューで送る（`mdaw_transport_*`）

## ビルド

### コアのテスト（PC）

```sh
cmake -S core -B build -DMDAW_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

### Android アプリ

必要なもの: Flutter（stable）、Android SDK と NDK、CMake 3.22.1（Android Studio の SDK Manager で入る）、JDK 17。

```sh
scripts/bootstrap_app.sh        # 初回だけ。Gradle ラッパーやアイコンなど雛形を生成する
cd app
flutter run --release           # 実機につないで起動
```

初回ビルドは JUCE と Oboe の取得・コンパイルで数分かかる。

### CI

push するたびに GitHub Actions がコアのテストと APK のビルドを行う。APK は Actions の実行結果の Artifacts（`mobiledaw-apk`）からもダウンロードできる。

### アップデート

- `main` に push すると、CI が固定の署名鍵で署名した APK を GitHub のリリース（タグ `build-<実行番号>`）に置く。リリースは新しい10件だけ残す
- アプリは起動時に最新リリースを確かめ、自分のビルド番号より新しければ画面上部に「アップデート」の帯を出す。「入れる」でダウンロードしてインストーラーが開く（初回だけ「この提供元のアプリを許可」が要る）
- 署名鍵は Actions のシークレット `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`。控えは持ち主の Google ドライブにある。シークレットが無いとデバッグ鍵で署名し、リリースは作らない

## ライセンス

自分用。AGPLv3（JUCE を AGPLv3 で使うため）。
