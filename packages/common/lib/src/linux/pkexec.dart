import 'dart:io';

Future<bool> pkexec(String file) async {
  final res = await Process.run('pkexec', [file]);

  return res.exitCode == 0;
}
