import 'dart:io';

Future<bool> pkexec(String file) async {
  final res = await Process.run('pkexec', [file]);

  return res.exitCode == 0;
}

Future<void> installSystemdService(String exePath) async {
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

[Install]
WantedBy=multi-user.target
''';

  // 2. 合并为一次提权执行
  //    写入文件 -> daemon-reload -> enable -> start
  final script =
      '''
cat > /etc/systemd/system/my-service.service << 'EOF'
$serviceContent
EOF
systemctl daemon-reload
systemctl enable my-service.service
systemctl start my-service.service
''';

  await Process.run('pkexec', ['sh', '-c', script]);
}
