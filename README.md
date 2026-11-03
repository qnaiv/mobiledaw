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

## 現在地：M1（音が鳴る）

`app/` は「音出しテスト」画面だけを持つ。C minor の鍵盤を触ると鳴り、出力遅延・バッファ・音切れ回数が見られる。

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

push するたびに GitHub Actions がコアのテストと APK のビルドを行う。APK は Actions の実行結果の Artifacts（`mobiledaw-apk`）からダウンロードして実機に入れられる。

## ライセンス

自分用。AGPLv3（JUCE を AGPLv3 で使うため）。
