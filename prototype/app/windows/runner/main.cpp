#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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
  const bool measuring=command_line && wcsstr(command_line, L"--benchmark=")!=nullptr;
  Win32Window::Size size(measuring?1936:1904, measuring?1119:1001);
  if (!window.Create(L"별여울 아카이브 - 성능 시제품", origin, size)) {
    return EXIT_FAILURE;
  }
  // 계측 때만 이 앱의 테두리를 제외해 실제 표시 영역을 1920×1080으로 맞춘다.
  if (measuring) {
    const HWND handle=window.GetHandle();
    SetWindowLongPtr(handle, GWL_STYLE, WS_POPUP);
    SetWindowPos(handle, nullptr, 0, 0, 1920, 1080, SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOACTIVATE);
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
