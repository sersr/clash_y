import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:utils/utils.dart';
import 'package:win32/win32.dart';

void windowEntryPoint(args) async {
  regClassName();
  _ceateWindow();

  final msg = calloc<MSG>();
  final s = args as SendPort;
  final rec = ReceivePort();

  s.send(rec.sendPort);
  rec.listen((message) {
    Log.w(message);
  });

  while (true) {
    await releaseUI;
    final re = PeekMessage(msg, NULL, 0, 0, PM_REMOVE);
    if (re != 0) {
      if (msg.ref.message == WM_QUIT) {
        break;
      }
      TranslateMessage(msg);
      DispatchMessage(msg);
    }
  }
  free(msg);
  // 确保退出
  Isolate.current.kill();
}

const _winClassName = '_FFI_windows';
void regClassName() {
  final lpClassName = TEXT(_winClassName);
  final wncs = calloc<WNDCLASS>();
  wncs.ref
    ..hCursor = LoadCursor(NULL, IDC_ARROW)
    ..lpszClassName = lpClassName
    ..style = CS_HREDRAW | CS_VREDRAW
    ..cbClsExtra = 0
    ..cbWndExtra = 0
    ..hInstance = GetModuleHandle(nullptr)
    ..hIcon = LoadIcon(wncs.ref.hInstance, Pointer.fromAddress(101))
    ..hbrBackground = 0
    ..lpszMenuName = nullptr
    ..lpfnWndProc = Pointer.fromFunction(wndProc, 0);
  RegisterClass(wncs);
  free(lpClassName);
  free(wncs);
}

int wndProc(int hWnd, int uMsg, int wParam, int lParam) {
  switch (uMsg) {
    case WM_DESTROY:
      DestroyWindow(hWnd);
      final s = TEXT(_winClassName);
      UnregisterClass(s, NULL);
      PostQuitMessage(0);
      break;
    default:
      return DefWindowProc(hWnd, uMsg, wParam, lParam);
  }
  return 0;
}

void _ceateWindow() {
  final lpClassName = TEXT(_winClassName);
  final lpWindowName = TEXT('hello ffi');
  final hwnd = CreateWindow(lpClassName, lpWindowName, WS_OVERLAPPEDWINDOW, 50,
      50, 400, 720, NULL, NULL, GetModuleHandle(nullptr), nullptr);

  ShowWindow(hwnd, SW_SHOWNORMAL);
  UpdateWindow(hwnd);
  free(lpClassName);
  free(lpWindowName);
}
