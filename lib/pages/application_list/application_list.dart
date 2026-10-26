import 'package:common/common.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';

import 'controller/application_list_controller.dart';
import 'widget/application_list_item.dart';

class ApplicationListPage extends StatefulWidget {
  const ApplicationListPage({super.key});

  @override
  State<ApplicationListPage> createState() => _ApplicationListPageState();
}

class _ApplicationListPageState extends State<ApplicationListPage> {
  late final ApplicationListController _controller = getType();

  @override
  Widget build(BuildContext context) {
    return SystemUI(
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F0F0),
        appBar: AppBar(
          title: const Text('Application list'),
          backgroundColor: const Color(0xFFF0F0F0),
          surfaceTintColor: Colors.transparent,
        ),
        body: Cs(
          () => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Blacklist')),
                        ButtonSegment(value: true, label: Text('Whitelist')),
                      ],
                      selected: {_controller.isAllowList},
                      onSelectionChanged: (selection) =>
                          _controller.switchMode(selection.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _controller.isAllowList
                          ? 'Only selected applications use the VPN.'
                          : 'Selected applications bypass the VPN.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Text(
                      'Changes are used the next time the VPN starts.',
                      style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show system applications'),
                      value: _controller.showSystemApps,
                      onChanged: _controller.setShowSystemApps,
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search applications',
                        prefixIcon: Icon(Icons.search),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                      onChanged: _controller.setSearchText,
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Selected: ${_controller.selectedPackages.length}',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _applicationList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _applicationList() {
    if (_controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.loadError case final error?) {
      return Center(child: Text(error));
    }
    final applications = _controller.visibleApplications;
    if (applications.isEmpty) {
      return const Center(child: Text('No applications found.'));
    }

    return ListView.builder(
      itemCount: applications.length,
      itemBuilder: (context, index) {
        final application = applications[index];
        return Cs(() {
          return ApplicationListItem(
            application: application,
            selected: _controller.selectedPackages.contains(
              application.packageName,
            ),
            onTap: () => _controller.toggleApplication(application.packageName),
          );
        });
      },
    );
  }
}
