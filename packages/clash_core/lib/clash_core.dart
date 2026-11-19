import 'dart:ffi' as ffi;

import 'src/clash_core.dart' as native;
import 'src/clash_core_macos.dart' as macos;

bool get _useDynamicLibrary => macos.dylibIsValid;

void configureMacOSLibraryPath(String path) {
  macos.configureLibraryPath(path);
}

/// Starts the core with the configuration found in configDir, mirroring
/// `mihomo -d configDir`. TUN follows whatever the config file declares.
ffi.Pointer<ffi.Char> start(ffi.Pointer<ffi.Char> configDir) =>
    _useDynamicLibrary ? macos.start(configDir) : native.start(configDir);

/// Starts the core with TUN enabled when given a TUN descriptor.
/// A positive fd is Android's VpnService descriptor; -1 requests a
/// helper-managed descriptor on macOS; 0 starts the core with TUN disabled.
ffi.Pointer<ffi.Char> startTun(ffi.Pointer<ffi.Char> configDir, int fd) =>
    _useDynamicLibrary
    ? macos.startTun(configDir, fd)
    : native.startTun(configDir, fd);

/// Stops the core and closes every listener, including TUN.
ffi.Pointer<ffi.Char> stop() =>
    _useDynamicLibrary ? macos.stop() : native.stop();

/// Stops only the desktop TUN listener, keeping the core process restartable.
ffi.Pointer<ffi.Char> stopTun() =>
    _useDynamicLibrary ? macos.stopTun() : native.stopTun();

/// Releases a string returned by this library.
void freeString(ffi.Pointer<ffi.Char> s) =>
    _useDynamicLibrary ? macos.freeString(s) : native.freeString(s);
