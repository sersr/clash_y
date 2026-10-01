import 'dart:io';

Future<int> installSystemdService() async {
  final exePath = Platform.resolvedExecutable;

  // 1. 构造 .service 文件内容
  final serviceContent =
      '''
[Unit]
Description=Clash VPN
After=network-online.target nftables.service iptables.service
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
ExecStart=$exePath --daemon
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
''';

  // 2. 合并为一次提权执行
  //    写入文件 -> daemon-reload -> enable -> start
  //   final script =
  //       '''
  // cat > /etc/systemd/system/clashy-service.service << 'EOF'
  // $serviceContent
  // EOF
  // systemctl daemon-reload
  // systemctl enable clashy-service.service
  // systemctl start clashy-service.service
  // ''';
  // await Process.run('pkexec', ['sh', '-c', script]);

  final file = File('/etc/systemd/system/clashy-service.service');
  await file.create(recursive: true);
  await file.writeAsString(serviceContent);

  final script = '''
systemctl daemon-reload
systemctl enable clashy-service.service
systemctl start clashy-service.service
''';

  final result = await Process.run('sh', ['-c', script]);
  return result.exitCode;
}

Future<int> stopSystemdService() async {
  final script = '''
systemctl disable --now clashy-service.service
systemctl daemon-reload
''';
  final result = await Process.run('sh', ['-c', script]);
  return result.exitCode;
}
