import 'package:material_ui/material_ui.dart';

import 'init.dart';
import 'pages/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initMain();

  runApp(const ClashApp());
}
