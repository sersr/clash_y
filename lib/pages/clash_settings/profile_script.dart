import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:material_ui/material_ui.dart';

class ProfileScriptPage extends StatefulWidget {
  const new({super.key});

  @override
  State<ProfileScriptPage> createState() => _ProfileScriptPageState();
}

class _ProfileScriptPageState extends State<ProfileScriptPage> {
  @override
  Widget build(BuildContext context) {
    final appbar = BaseAppBar(
      leading: const BaseBackButton.black(),
      center: Text(
        'Scripts',
        style: .new(color: Colors.black, fontSize: 18.sp, fontWeight: .w500),
      ),
    );


    return  BaseScaffold(appbar: appbar, body: body.cs);
  }

  Widget body(BuildContext context) {
    return SizedBox();
  }
}
