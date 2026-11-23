import 'src/dart_ipc_platform_interface.dart' show DartIpcPlatform;

export 'src/dart_ipc_stub.dart' if (dart.library.io) 'src/dart_ipc_io.dart';

/// Configures the ACL used by subsequently bound Windows named pipes.
void configureWindowsServerSecurityDescriptor(String descriptor) {
  DartIpcPlatform.configureWindowsServerSecurityDescriptor(descriptor);
}
