import 'package:hooks/hooks.dart';

import '_build.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildWakeMonitor(input, output);
    await buildClashServer(input, output);
  });
}
