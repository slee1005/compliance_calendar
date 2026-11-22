#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>
#include <string>

#include "win32_window.h"

struct DocumentReadLifetime;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void InitializeDocumentInput();
  void ClearDocumentInput();
  std::string StageDocumentFile(const std::wstring& path);
  bool input_enabled_ = false;
  bool input_reading_ = false;
  ULONGLONG input_expires_ = 0;
  uint64_t input_counter_ = 0;
  std::string input_token_;
  std::wstring input_path_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> input_channel_;
  std::shared_ptr<DocumentReadLifetime> input_lifetime_;
  void ConcealPrivacy(const char* state);
  void EmitPrivacy(const char* state);
  flutter::EncodableValue PrivacyStatus() const;
  HWND privacy_cover_ = nullptr;
  int64_t privacy_epoch_ = 0;
  bool session_active_ = true;
  bool capture_protected_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> privacy_channel_;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
