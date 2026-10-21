#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (::AttachConsole(ATTACH_PARENT_PROCESS)) {
    RedirectOutputToConsole();
  } else if (::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // One instance only: the app may be running hidden in the system tray
  // (lib/services/desktop_background_service.dart), so a second launch
  // brings that window back instead of opening the database twice.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\WarchatiErpAluminiumInstance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    const bool start_minimized =
        std::wstring(command_line).find(L"--minimized") != std::wstring::npos;
    HWND existing =
        ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"database_data");
    if (existing != nullptr && !start_minimized) {
      if (!::IsWindowVisible(existing)) {
        ::ShowWindow(existing, SW_SHOWMAXIMIZED);
      } else if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      }
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
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
  if (!window.Create(L"database_data", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::ExitProcess(0);
  return EXIT_SUCCESS;
}

int main() {
  return wWinMain(::GetModuleHandle(nullptr), nullptr, ::GetCommandLineW(),
                  SW_SHOWNORMAL);
}
