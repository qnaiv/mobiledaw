#!/usr/bin/env bash
# Flutter の雛形（Gradle ラッパー、アイコン、テーマなど）のうち、リポジトリに無いものを生成する。
# 既にあるファイル（build.gradle.kts, AndroidManifest.xml, MainActivity.java など）は上書きされない。
set -euo pipefail

cd "$(dirname "$0")/../app"

flutter create --platforms=android --org com.qnaiv --project-name mobiledaw .

# このリポジトリは Java の MainActivity を使うので、雛形の Kotlin 版は消す
rm -rf android/app/src/main/kotlin

# 雛形のサンプルテスト（MyApp 前提）は不要
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then
  rm test/widget_test.dart
fi

flutter pub get
