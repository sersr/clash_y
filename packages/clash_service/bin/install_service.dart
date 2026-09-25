import 'dart:io';

import 'package:clash_service/clash_service.dart';
import 'package:nop/nop.dart';
import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart';

export 'package:dart_service_manager/dart_service_manager.dart'
    show ServiceStatus;

const servicePackageName = 'clashy';
const serviceName = 'clashyHelper';

abstract final class Services {
  static final manager = DartServiceManager.forCurrentPlatform(
    logger: ConsoleServiceLogger(),
  );

  static Future<ServiceStatus> start(List<String> args) async {
    final currentDir = fs.currentDirectory
        .childFile(Platform.resolvedExecutable)
        .parent;
    final suf = Platform.isWindows ? '.exe' : '';
    final exe = join(currentDir.path, 'clashHelper$suf');
    ServiceStatus? status;
    try {
      status = await manager.status(serviceName, serviceName);
    } catch (_) {}

    switch (status) {
      case ServiceStatus.installed:
      case ServiceStatus.running:
      case ServiceStatus.paused:
      case ServiceStatus.stopped:
        Log.w('service: $status');
        await manager.reconfigure(
          .new(
            packageName: servicePackageName,
            serviceName: serviceName,
            executablePath: exe,
            scope: .system,
            restart: .onFailure,
            arguments: args,
            description: 'Clash VPN',
          ),
        );
        manager.start(servicePackageName, serviceName);
        break;
      case ServiceStatus.failed:
        manager.start(servicePackageName, serviceName);

      case ServiceStatus.unknown || null:
        await manager.installDescriptor(
          .new(
            packageName: servicePackageName,
            serviceName: serviceName,
            executablePath: exe,
            scope: .system,
            restart: .onFailure,
            arguments: args,
            description: 'Clash VPN',
          ),
          startNow: true,
        );
    }

    return manager.status(serviceName, serviceName);
  }

  // static Future<ServiceStatus?> stop() async {
  //   await manager.stop(servicePackageName, serviceName);
  //   ServiceStatus? status;
  //   try {
  //     status = await manager.status(serviceName, serviceName);
  //   } catch (_) {}
  //   return status;
  // }
}
