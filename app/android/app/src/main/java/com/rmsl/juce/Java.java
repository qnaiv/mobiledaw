package com.rmsl.juce;

import android.content.Context;

/**
 * JUCE が Android で動くための初期化の入り口。
 *
 * JUCE の juce_core は、ライブラリ読み込み時（JNI_OnLoad）にこのクラスを探して
 * initialiseJUCE にネイティブ実装を登録する。そのためクラス名とパッケージは
 * JUCE が期待する com.rmsl.juce.Java のままにしておく必要がある。
 * JUCE 同梱の Java.java と違い、読み込むのは自分たちの libmdaw.so。
 */
public final class Java {
    static {
        System.loadLibrary("mdaw");
    }

    private Java() {}

    public static native void initialiseJUCE(Context appContext);
}
