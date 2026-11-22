#include "flutter_window.h"

#include <optional>
#include <wtsapi32.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <commdlg.h>
#include <algorithm>
#include <cwctype>
#include <thread>
#include <vector>
#include <mutex>

#include "flutter/generated_plugin_registrant.h"

struct DocumentReadLifetime { std::mutex mutex; bool alive = true; };

namespace {
constexpr UINT kDocumentRead = WM_APP + 91;
constexpr UINT_PTR kDocumentExpiry = 0x6D6001;
constexpr DWORD kDocumentMaximum = 20 * 1024 * 1024;
struct DocumentReadReply {
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
  std::string token;
  std::vector<uint8_t> bytes;
  std::string error;
  ~DocumentReadReply() {
    if (!bytes.empty()) SecureZeroMemory(bytes.data(), bytes.size());
  }
};
bool AllowedLocalDocument(const std::wstring& path) {
  if (path.size() < 3 || path[1] != L':' || path[2] != L'\\') return false;
  const UINT drive = GetDriveTypeW(path.substr(0, 3).c_str());
  if (drive != DRIVE_FIXED && drive != DRIVE_REMOVABLE) return false;
  const auto dot = path.find_last_of(L'.');
  if (dot == std::wstring::npos) return false;
  auto extension = path.substr(dot);
  std::transform(extension.begin(), extension.end(), extension.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return extension == L".png" || extension == L".jpg" || extension == L".jpeg" ||
         extension == L".heic" || extension == L".heif" || extension == L".pdf";
}
void ReadLocalDocument(const std::wstring& path, DocumentReadReply& reply) {
  const DWORD attrs = GetFileAttributesW(path.c_str());
  if (attrs == INVALID_FILE_ATTRIBUTES ||
      (attrs & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_OFFLINE))) {
    reply.error = "unsupported"; return;
  }
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                           nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (file == INVALID_HANDLE_VALUE) { reply.error = "io"; return; }
  LARGE_INTEGER size{};
  FILE_ATTRIBUTE_TAG_INFO info{};
  if (GetFileType(file) != FILE_TYPE_DISK ||
      !GetFileInformationByHandleEx(file, FileAttributeTagInfo, &info, sizeof(info)) ||
      (info.FileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) {
    reply.error = "unsupported";
  } else if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 || size.QuadPart > kDocumentMaximum) {
    reply.error = "too_large";
  } else {
    reply.bytes.resize(static_cast<size_t>(size.QuadPart) + 1);
    DWORD count = 0;
    if (!ReadFile(file, reply.bytes.data(), static_cast<DWORD>(reply.bytes.size()), &count, nullptr) ||
        count != static_cast<DWORD>(size.QuadPart)) reply.error = "io";
    else reply.bytes.resize(count);
  }
  CloseHandle(file);
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  InitializeDocumentInput();
  capture_protected_ = SetWindowDisplayAffinity(GetHandle(), 0x00000011) != FALSE;
  WTSRegisterSessionNotification(GetHandle(), NOTIFY_FOR_THIS_SESSION);
  privacy_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.smallbizcompliance/privacy",
      &flutter::StandardMethodCodec::GetInstance());
  privacy_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "configure") {
      bool enabled = true;
      if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
        auto it = args->find(flutter::EncodableValue("enabled"));
        if (it != args->end() && std::holds_alternative<bool>(it->second)) enabled = std::get<bool>(it->second);
      }
      capture_protected_ = enabled && SetWindowDisplayAffinity(GetHandle(), 0x00000011) != FALSE;
      if (!enabled) SetWindowDisplayAffinity(GetHandle(), WDA_NONE);
      result->Success(PrivacyStatus());
    } else if (call.method_name() == "cover") {
      ConcealPrivacy(nullptr); result->Success(PrivacyStatus());
    } else if (call.method_name() == "reveal") {
      int64_t epoch = -1;
      if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
        auto it = args->find(flutter::EncodableValue("epoch"));
        if (it != args->end()) {
          if (std::holds_alternative<int32_t>(it->second)) epoch = std::get<int32_t>(it->second);
          if (std::holds_alternative<int64_t>(it->second)) epoch = std::get<int64_t>(it->second);
        }
      }
      if (session_active_ && GetForegroundWindow() == GetHandle() && epoch == privacy_epoch_ && privacy_cover_) {
        ShowWindow(privacy_cover_, SW_HIDE);
      }
      result->Success(PrivacyStatus());
    } else if (call.method_name() == "status") result->Success(PrivacyStatus());
    else result->NotImplemented();
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (input_lifetime_) {
    std::lock_guard<std::mutex> lock(input_lifetime_->mutex);
    input_lifetime_->alive = false;
    MSG queued{};
    while (PeekMessageW(&queued, GetHandle(), kDocumentRead, kDocumentRead, PM_REMOVE)) {
      delete reinterpret_cast<DocumentReadReply*>(queued.lParam);
    }
  }
  input_enabled_ = false;
  ClearDocumentInput();
  input_channel_.reset();
  WTSUnRegisterSessionNotification(GetHandle());
  privacy_channel_.reset();
  if (privacy_cover_) { DestroyWindow(privacy_cover_); privacy_cover_ = nullptr; }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kDocumentRead) {
    std::unique_ptr<DocumentReadReply> reply(reinterpret_cast<DocumentReadReply*>(lparam));
    if (!input_enabled_ || input_token_ != reply->token || GetTickCount64() >= input_expires_) {
      reply->result->Error("expired");
    } else if (!reply->error.empty()) reply->result->Error(reply->error);
    else reply->result->Success(flutter::EncodableValue(reply->bytes));
    return 0;
  }
  if (message == WM_TIMER && wparam == kDocumentExpiry) { ClearDocumentInput(); return 0; }
  if (message == WM_DROPFILES) {
    HDROP drop = reinterpret_cast<HDROP>(wparam);
    if (input_enabled_ && DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0) == 1) {
      const UINT length = DragQueryFileW(drop, 0, nullptr, 0);
      if (length > 0 && length < 32768) {
        std::wstring path(length + 1, L'\0');
        DragQueryFileW(drop, 0, path.data(), length + 1); path.resize(length);
        const auto token = StageDocumentFile(path);
        SecureZeroMemory(path.data(), path.size() * sizeof(wchar_t));
        if (!token.empty()) {
          SetForegroundWindow(hwnd);
          input_channel_->InvokeMethod("drop", std::make_unique<flutter::EncodableValue>(token));
        }
      }
    }
    DragFinish(drop); return 0;
  }
  // Cover synchronously before Flutter processes focus/background messages.
  if (message == WM_ACTIVATE) {
    if (LOWORD(wparam) == WA_INACTIVE) ConcealPrivacy("inactive");
    else { ++privacy_epoch_; EmitPrivacy(session_active_ ? "foreground" : "inactive"); }
  } else if (message == WM_POWERBROADCAST) {
    if (wparam == PBT_APMSUSPEND) ConcealPrivacy("locked");
    else if (wparam == PBT_APMRESUMEAUTOMATIC || wparam == PBT_APMRESUMESUSPEND) {
      ++privacy_epoch_;
      EmitPrivacy(session_active_ && GetForegroundWindow() == GetHandle() ? "foreground" : "inactive");
    }
  } else if (message == WM_WTSSESSION_CHANGE) {
    if (wparam == WTS_SESSION_LOCK) { session_active_ = false; ConcealPrivacy("locked"); }
    else if (wparam == WTS_SESSION_UNLOCK) { session_active_ = true; ++privacy_epoch_; EmitPrivacy("foreground"); }
  } else if (message == WM_SIZE && privacy_cover_) {
    RECT rect = GetClientArea();
    SetWindowPos(privacy_cover_, HWND_TOP, 0, 0, rect.right, rect.bottom, SWP_NOACTIVATE);
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::ClearDocumentInput() {
  KillTimer(GetHandle(), kDocumentExpiry);
  if (!input_path_.empty()) SecureZeroMemory(input_path_.data(), input_path_.size() * sizeof(wchar_t));
  input_path_.clear(); input_token_.clear(); input_expires_ = 0; input_reading_ = false;
}
std::string FlutterWindow::StageDocumentFile(const std::wstring& path) {
  if (!input_enabled_ || !AllowedLocalDocument(path)) return {};
  ClearDocumentInput();
  input_path_ = path;
  input_token_ = std::to_string(GetTickCount64()) + ":" + std::to_string(++input_counter_);
  input_expires_ = GetTickCount64() + 10000;
  SetTimer(GetHandle(), kDocumentExpiry, 10000, nullptr);
  return input_token_;
}
void FlutterWindow::InitializeDocumentInput() {
  input_lifetime_ = std::make_shared<DocumentReadLifetime>();
  input_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.smallbizcompliance/input",
      &flutter::StandardMethodCodec::GetInstance());
  input_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "enable") {
      const auto* enabled = std::get_if<bool>(call.arguments());
      input_enabled_ = enabled && *enabled;
      DragAcceptFiles(GetHandle(), input_enabled_);
      if (!input_enabled_) ClearDocumentInput();
      result->Success();
    } else if (call.method_name() == "pick") {
      if (!input_enabled_) { result->Error("inactive"); return; }
      std::vector<wchar_t> path(32768, L'\0');
      OPENFILENAMEW dialog{}; dialog.lStructSize = sizeof(dialog); dialog.hwndOwner = GetHandle();
      dialog.lpstrFile = path.data(); dialog.nMaxFile = static_cast<DWORD>(path.size());
      dialog.lpstrFilter = L"Images and PDF\0*.png;*.jpg;*.jpeg;*.heic;*.heif;*.pdf\0\0";
      dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_NODEREFERENCELINKS;
      const bool selected = GetOpenFileNameW(&dialog) != FALSE;
      const auto token = selected ? StageDocumentFile(path.data()) : std::string();
      SecureZeroMemory(path.data(), path.size() * sizeof(wchar_t));
      if (token.empty()) result->Success(); else result->Success(flutter::EncodableValue(token));
    } else if (call.method_name() == "release") {
      const auto* token = std::get_if<std::string>(call.arguments());
      if (token && *token == input_token_) ClearDocumentInput();
      result->Success();
    } else if (call.method_name() == "read") {
      const auto* token = std::get_if<std::string>(call.arguments());
      if (!input_enabled_ || GetForegroundWindow() != GetHandle()) { result->Error("inactive"); return; }
      if (!token || *token != input_token_ || input_reading_ || GetTickCount64() >= input_expires_) {
        result->Error("expired"); return;
      }
      input_reading_ = true;
      auto* reply = new DocumentReadReply(); reply->result = std::move(result); reply->token = *token;
      const HWND window = GetHandle();
      std::thread([window, path = input_path_, reply, lifetime = input_lifetime_]() mutable {
        ReadLocalDocument(path, *reply);
        SecureZeroMemory(path.data(), path.size() * sizeof(wchar_t));
        std::lock_guard<std::mutex> lock(lifetime->mutex);
        if (!lifetime->alive || !PostMessageW(window, kDocumentRead, 0, reinterpret_cast<LPARAM>(reply))) delete reply;
      }).detach();
    } else if (call.method_name() == "status") {
      result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("pending"), flutter::EncodableValue(input_token_.empty() ? 0 : 1)},
        {flutter::EncodableValue("enabled"), flutter::EncodableValue(input_enabled_)}}));
    } else result->NotImplemented();
  });
}


void FlutterWindow::EmitPrivacy(const char* state) {
  if (!privacy_channel_ || !state) return;
  privacy_channel_->InvokeMethod("visibility", std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
    {flutter::EncodableValue("epoch"), flutter::EncodableValue(privacy_epoch_)},
    {flutter::EncodableValue("state"), flutter::EncodableValue(state)}}));
}
void FlutterWindow::ConcealPrivacy(const char* state) {
  ++privacy_epoch_;
  RECT rect = GetClientArea();
  if (!privacy_cover_) {
    privacy_cover_ = CreateWindowExW(0, L"STATIC", L"화면 보호 중", WS_CHILD | SS_CENTER,
      0, 0, rect.right, rect.bottom, GetHandle(), nullptr, GetModuleHandle(nullptr), nullptr);
  }
  if (privacy_cover_) {
    SetWindowPos(privacy_cover_, HWND_TOP, 0, 0, rect.right, rect.bottom, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    UpdateWindow(privacy_cover_);
  }
  EmitPrivacy(state);
}
flutter::EncodableValue FlutterWindow::PrivacyStatus() const {
  return flutter::EncodableValue(flutter::EncodableMap{
    {flutter::EncodableValue("epoch"), flutter::EncodableValue(privacy_epoch_)},
    {flutter::EncodableValue("active"), flutter::EncodableValue(session_active_ && GetForegroundWindow() == GetHandle())},
    {flutter::EncodableValue("cover"), flutter::EncodableValue(true)},
    {flutter::EncodableValue("capture"), flutter::EncodableValue(capture_protected_)},
    {flutter::EncodableValue("files"), flutter::EncodableValue(false)},
    {flutter::EncodableValue("covered"), flutter::EncodableValue(privacy_cover_ && IsWindowVisible(privacy_cover_))}});
}
