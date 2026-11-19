import 'package:hooks/hooks.dart';

import '_build.dart';

extension on BuildInput {
  bool get isFlutter {
    return userDefines['isFlutter'] == true;
  }
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.isFlutter) return;
    await buildWakeMonitor(input, output);
    await buildTrayExecutable(input, output);
    await buildClashServer(input, output);
  });
}
