package com.qnaiv.mobiledaw;

import android.os.Bundle;

import io.flutter.embedding.android.FlutterActivity;

public class MainActivity extends FlutterActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // libmdaw.so を読み込み、JUCE の Android 側の初期化を済ませる。
        // Dart 側の DynamicLibrary.open('libmdaw.so') より先に行う必要がある。
        com.rmsl.juce.Java.initialiseJUCE(getApplicationContext());
        super.onCreate(savedInstanceState);
    }
}
