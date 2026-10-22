import 'package:flutter/material.dart';

import '../controller/application_list_controller.dart';

class ApplicationListItem extends StatelessWidget {
  const ApplicationListItem({
    super.key,
    required this.application,
    required this.selected,
    required this.onTap,
  });

  final InstalledApplication application;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: application.icon == null
          ? const CircleAvatar(child: Icon(Icons.android))
          : Image.memory(
              application.icon!,
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
      title: Text(
        application.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        application.packageName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Checkbox.adaptive(value: selected, onChanged: (_) => onTap()),
      onTap: onTap,
    );
  }
}
