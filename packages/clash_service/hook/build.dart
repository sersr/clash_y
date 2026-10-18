import 'package:hooks/hooks.dart';
import 'package:clash_service/build.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await [
      buildClashServer(input, output),
    ].wait;
  });
}
