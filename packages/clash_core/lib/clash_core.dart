import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'src/clash_core.dart' as native;
import 'src/clash_core_macos.dart' as macos;

bool get _useDynamicLibrary => Platform.isMacOS;

/// Starts the core with the configuration found in configDir, mirroring
/// `mihomo -d configDir`. TUN follows whatever the config file declares.
ffi.Pointer<ffi.Char> start(ffi.Pointer<ffi.Char> configDir) =>
    _useDynamicLibrary ? macos.start(configDir) : native.start(configDir);

/// Starts the core like start(), but forces `tun.enable` to true. While the core
/// is running this only (re)creates the TUN listener.
///
/// fd is the descriptor of the tun device an Android VpnService already
/// established, and must be transferred to the core: it takes ownership and
/// closes it on shutdown, so do not close the ParcelFileDescriptor as well.
/// Pass 0 (or a negative value) when the core may create the device itself.
ffi.Pointer<ffi.Char> startTun(ffi.Pointer<ffi.Char> configDir, int fd) =>
    _useDynamicLibrary
    ? macos.startTun(configDir, fd)
    : native.startTun(configDir, fd);

/// Stops the core and closes every listener, including TUN.
ffi.Pointer<ffi.Char> stop() =>
    _useDynamicLibrary ? macos.stop() : native.stop();

/// Releases a string returned by this library.
void freeString(ffi.Pointer<ffi.Char> s) =>
    _useDynamicLibrary ? macos.freeString(s) : native.freeString(s);
