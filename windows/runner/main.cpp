#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kWindowTitle[] = L"fyp_test";
constexpr const wchar_t kAuthScheme[] = L"notebooktutor";

void RegisterAuthProtocol() {
  wchar_t executable_path[MAX_PATH];
  if (::GetModuleFileNameW(nullptr, executable_path, MAX_PATH) == 0) {
    return;
  }

  const std::wstring base_key =
      std::wstring(L"Software\\Classes\\") + kAuthScheme;
  const std::wstring description = L"URL:Notebook Tutor authentication";
  const std::wstring command_key = base_key + L"\\shell\\open\\command";
  const std::wstring command =
      std::wstring(L"\"") + executable_path + L"\" \"%1\"";
  const wchar_t empty_value[] = L"";

  ::RegSetKeyValueW(HKEY_CURRENT_USER, base_key.c_str(), nullptr, REG_SZ,
                    description.c_str(),
                    static_cast<DWORD>((description.size() + 1) *
                                       sizeof(wchar_t)));
  ::RegSetKeyValueW(HKEY_CURRENT_USER, base_key.c_str(), L"URL Protocol",
                    REG_SZ, empty_value, sizeof(empty_value));
  ::RegSetKeyValueW(HKEY_CURRENT_USER, command_key.c_str(), nullptr, REG_SZ,
                    command.c_str(),
                    static_cast<DWORD>((command.size() + 1) *
                                       sizeof(wchar_t)));
}

bool SendAuthLinkToRunningInstance() {
  HWND window =
      ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
  if (!window) return false;

  SendAppLink(window);
  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  } else {
    ::ShowWindow(window, SW_SHOW);
  }
  ::SetForegroundWindow(window);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  RegisterAuthProtocol();
  if (SendAuthLinkToRunningInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
