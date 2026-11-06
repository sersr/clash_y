import 'package:install_apps/install_apps.dart';
import 'package:material_ui/material_ui.dart';

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
      leading: Image(
        image: AppIconImageProvider(application.packageName),

        width: 40,
        height: 40,
        fit: BoxFit.contain,
      ),
      title: Text(
        application.appName,
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
