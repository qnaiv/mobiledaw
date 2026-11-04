package com.qnaiv.mobiledaw;

import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    // lib/update/updater.dart と揃える
    private static final String UPDATER_CHANNEL = "mobiledaw/updater";
    // lib/platform_paths.dart と揃える
    private static final String PATHS_CHANNEL = "mobiledaw/paths";
    // lib/export/share.dart と揃える
    private static final String SHARE_CHANNEL = "mobiledaw/share";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // libmdaw.so を読み込み、JUCE の Android 側の初期化を済ませる。
        // Dart 側の DynamicLibrary.open('libmdaw.so') より先に行う必要がある。
        com.rmsl.juce.Java.initialiseJUCE(getApplicationContext());
        super.onCreate(savedInstanceState);
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), PATHS_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (call.method.equals("filesDir")) {
                        // アプリ専用の保存場所（アンインストールで消える。バックアップは書き出しで行う）
                        result.success(getFilesDir().getAbsolutePath());
                    } else {
                        result.notImplemented();
                    }
                });
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SHARE_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "exportsDir": {
                            // res/xml/update_paths.xml の cache-path「exports」と同じ場所
                            File dir = new File(getCacheDir(), "exports");
                            //noinspection ResultOfMethodCallIgnored
                            dir.mkdirs();
                            result.success(dir.getAbsolutePath());
                            break;
                        }
                        case "share": {
                            List<String> paths = call.argument("paths");
                            String mime = call.argument("mimeType");
                            String title = call.argument("title");
                            try {
                                shareFiles(paths, mime, title);
                                result.success(null);
                            } catch (Exception e) {
                                result.error("share", e.toString(), null);
                            }
                            break;
                        }
                        default:
                            result.notImplemented();
                    }
                });
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), UPDATER_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "updatesDir": {
                            // res/xml/update_paths.xml の cache-path と同じ場所
                            File dir = new File(getCacheDir(), "updates");
                            //noinspection ResultOfMethodCallIgnored
                            dir.mkdirs();
                            result.success(dir.getAbsolutePath());
                            break;
                        }
                        case "installApk": {
                            String path = call.argument("path");
                            result.success(installApk(path));
                            break;
                        }
                        default:
                            result.notImplemented();
                    }
                });
    }

    /** 書き出したファイルを共有シートへ（1つなら ACTION_SEND、複数なら ACTION_SEND_MULTIPLE） */
    private void shareFiles(List<String> paths, String mime, String title) {
        if (paths == null || paths.isEmpty())
            throw new IllegalArgumentException("no files");
        ArrayList<Uri> uris = new ArrayList<>();
        for (String p : paths)
            uris.add(FileProvider.getUriForFile(this, getPackageName() + ".updates", new File(p)));
        Intent send;
        if (uris.size() == 1) {
            send = new Intent(Intent.ACTION_SEND);
            send.putExtra(Intent.EXTRA_STREAM, uris.get(0));
        } else {
            send = new Intent(Intent.ACTION_SEND_MULTIPLE);
            send.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
        }
        send.setType(mime != null ? mime : "*/*");
        if (title != null)
            send.putExtra(Intent.EXTRA_SUBJECT, title);
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        Intent chooser = Intent.createChooser(send, title != null ? title : "書き出したファイル");
        chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivity(chooser);
    }

    /**
     * ダウンロード済みの APK をシステムのインストーラーへ渡す。
     * 「この提供元のアプリを許可」がまだなら設定画面を開いて "needsPermission" を返す。
     */
    private String installApk(String path) {
        if (path == null)
            return "error";
        File file = new File(path);
        if (!file.isFile())
            return "error";

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && !getPackageManager().canRequestPackageInstalls()) {
            Intent settings = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + getPackageName()));
            startActivity(settings);
            return "needsPermission";
        }

        Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".updates", file);
        Intent install = new Intent(Intent.ACTION_VIEW);
        install.setDataAndType(uri, "application/vnd.android.package-archive");
        install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(install);
        return "started";
    }
}
