import 'package:clashy/_route/routes.dart';
import 'package:common/common.dart';
import 'package:material_ui/material_ui.dart';

class ProfileScriptItem extends StatelessWidget {
  const new({super.key, required this.item, required this.id});
  final ProfileScriptModel item;
  final String id;
  @override
  Widget build(BuildContext context) {
    final nameW = Text(
      item.name,
      style: .new(color: const Color.fromARGB(255, 62, 62, 62)),
    );

    final editW = Icon(
      Icons.edit_sharp,
      size: 22,
      color: const Color.fromARGB(255, 32, 132, 239),
    );


    Widget content = Row(children: [nameW.expanded, editW]);

    content = Container(
      decoration: BoxDecoration(
        borderRadius: .circular(12),
        color: Colors.white,
      ),
      padding: .symmetric(horizontal: 16.w, vertical: 12.h),
      margin: .symmetric(horizontal: 12.w, vertical: 8.h),
      child: content,
    );

    content = GestureDetector(
      onTap: () {
        NavRoutes.scriptEdit(item: item, id: id).go();
      },
      child: content,
    );

    return content;
  }
}
