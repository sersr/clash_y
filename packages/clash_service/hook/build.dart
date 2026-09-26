import 'package:hooks/hooks.dart';
import 'package:clash_service/build.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await [
      buildMacOSDaemon(input, output),
      buildClashServer(input, output),
    ].wait;
  });
}
