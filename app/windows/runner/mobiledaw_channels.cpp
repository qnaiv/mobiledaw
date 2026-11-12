#include "mobiledaw_channels.h"

#include <windows.h>
#include <commdlg.h>
#include <shellapi.h>
#include <shlobj.h>

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodCall = flutter::MethodCall<EncodableValue>;
using MethodResult = flutter::MethodResult<EncodableValue>;

// チャネルはアプリの生存期間ずっと必要なので、登録側で保持する。
std::vector<std::unique_ptr<flutter::MethodChannel<EncodableValue>>> g_channels;

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  const int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                                       nullptr, 0, nullptr, nullptr);
  std::string out(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), out.data(), size,
                      nullptr, nullptr);
  return out;
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                                       nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), out.data(), size);
  return out;
}

const EncodableValue* FindArg(const EncodableValue& args, const char* key) {
  const auto* map = std::get_if<EncodableMap>(&args);
  if (map == nullptr) return nullptr;
  const auto it = map->find(EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

std::wstring ArgString(const EncodableValue& args, const char* key) {
  const EncodableValue* value = FindArg(args, key);
  const auto* text = value == nullptr ? nullptr : std::get_if<std::string>(value);
  return text == nullptr ? std::wstring() : Utf8ToWide(*text);
}

// アプリ専用の保存場所：%APPDATA%\mobiledaw（Android の filesDir 相当。無ければ作る）
std::filesystem::path FilesDir() {
  std::filesystem::path base;
  PWSTR roaming = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &roaming)) &&
      roaming != nullptr) {
    base = roaming;
  }
  if (roaming != nullptr) CoTaskMemFree(roaming);
  if (base.empty()) base = std::filesystem::current_path();
  const std::filesystem::path dir = base / L"mobiledaw";
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  return dir;
}

void RegisterChannel(flutter::FlutterViewController* controller, const char* name,
                     flutter::MethodCallHandler<EncodableValue> handler) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      controller->engine()->messenger(), name, &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(std::move(handler));
  g_channels.push_back(std::move(channel));
}

// ダイアログのフィルタ（"<名前> (*.ext)\0*.ext\0All files (*.*)\0*.*\0\0"）
std::vector<wchar_t> BuildFilter(const std::wstring& name, const std::wstring& ext) {
  std::wstring filter;
  const auto append = [&filter](const std::wstring& part) {
    filter += part;
    filter.push_back(L'\0');
  };
  if (!ext.empty()) {
    append((name.empty() ? ext : name) + L" (*." + ext + L")");
    append(L"*." + ext);
  }
  append(L"All files (*.*)");
  append(L"*.*");
  filter.push_back(L'\0');
  return std::vector<wchar_t>(filter.begin(), filter.end());
}

HWND OwnerWindow(flutter::FlutterViewController* controller) {
  return GetAncestor(controller->view()->GetNativeWindow(), GA_ROOT);
}

}  // namespace

void RegisterMobiledawChannels(flutter::FlutterViewController* controller) {
  // mobiledaw/paths（lib/platform_paths.dart と揃える）
  RegisterChannel(controller, "mobiledaw/paths",
                  [](const MethodCall& call, std::unique_ptr<MethodResult> result) {
                    if (call.method_name() == "filesDir") {
                      result->Success(EncodableValue(WideToUtf8(FilesDir().wstring())));
                    } else {
                      result->NotImplemented();
                    }
                  });

  // mobiledaw/share（lib/export/share.dart と揃える）
  RegisterChannel(controller, "mobiledaw/share",
                  [](const MethodCall& call, std::unique_ptr<MethodResult> result) {
                    if (call.method_name() == "exportsDir") {
                      const std::filesystem::path dir = FilesDir() / L"exports";
                      std::error_code ec;
                      std::filesystem::create_directories(dir, ec);
                      result->Success(EncodableValue(WideToUtf8(dir.wstring())));
                    } else if (call.method_name() == "share") {
                      // 共有シートの代替：書き出したファイルを Explorer で選択表示する
                      const EncodableValue* paths_value = FindArg(*call.arguments(), "paths");
                      const auto* paths =
                          paths_value == nullptr ? nullptr : std::get_if<EncodableList>(paths_value);
                      if (paths == nullptr || paths->empty()) {
                        result->Error("share", "no files", nullptr);
                        return;
                      }
                      for (const EncodableValue& item : *paths) {
                        const auto* path = std::get_if<std::string>(&item);
                        if (path == nullptr) continue;
                        const std::wstring params = L"/select,\"" + Utf8ToWide(*path) + L"\"";
                        ShellExecuteW(nullptr, L"open", L"explorer.exe", params.c_str(), nullptr,
                                      SW_SHOWNORMAL);
                      }
                      result->Success();
                    } else {
                      result->NotImplemented();
                    }
                  });

  // mobiledaw/files（lib/platform_files.dart と揃える）
  RegisterChannel(controller, "mobiledaw/files",
                  [controller](const MethodCall& call, std::unique_ptr<MethodResult> result) {
                    const bool open = call.method_name() == "openFile";
                    if (!open && call.method_name() != "saveFile") {
                      result->NotImplemented();
                      return;
                    }
                    const std::wstring title = ArgString(*call.arguments(), "title");
                    const std::wstring default_name = ArgString(*call.arguments(), "defaultName");
                    const std::vector<wchar_t> filter = BuildFilter(
                        ArgString(*call.arguments(), "filterName"),
                        ArgString(*call.arguments(), "extension"));
                    const std::wstring ext = ArgString(*call.arguments(), "extension");

                    wchar_t file_buf[1024] = {};
                    if (!open && !default_name.empty() && default_name.size() < 1024) {
                      wcscpy_s(file_buf, default_name.c_str());
                    }
                    OPENFILENAMEW ofn = {};
                    ofn.lStructSize = sizeof(ofn);
                    ofn.hwndOwner = OwnerWindow(controller);
                    ofn.lpstrFilter = filter.data();
                    ofn.lpstrFile = file_buf;
                    ofn.nMaxFile = static_cast<DWORD>(sizeof(file_buf) / sizeof(file_buf[0]));
                    ofn.lpstrTitle = title.empty() ? nullptr : title.c_str();
                    if (!ext.empty()) ofn.lpstrDefExt = ext.c_str();
                    ofn.Flags = OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST |
                                (open ? OFN_FILEMUSTEXIST : OFN_OVERWRITEPROMPT);
                    const BOOL chosen = open ? GetOpenFileNameW(&ofn) : GetSaveFileNameW(&ofn);
                    if (chosen) {
                      result->Success(EncodableValue(WideToUtf8(file_buf)));
                    } else {
                      result->Success();  // やめた場合は null
                    }
                  });
}
