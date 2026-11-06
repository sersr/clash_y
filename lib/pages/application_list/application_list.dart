import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:material_ui/material_ui.dart';

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
    final menu = InkButton(
      onPressed: () {
        _settings();
      },
      shape: CircleBorder(),
      padding: .all(10),
      backgroundColor: Colors.transparent,
      overlayColor: const Color.fromARGB(61, 181, 181, 181),
      child: Icon(Icons.more_vert_rounded, size: 20),
    );

    final saveW = IntrinsicWidth(
      child: Center(
        child: Padding(
          padding: .only(left: 10.w),
          child: InkButton(
            backgroundColor: const Color.fromARGB(255, 238, 237, 237),
            overlayColor: const Color.fromARGB(74, 198, 198, 198),
            isStadium: true,
            padding: .symmetric(horizontal: 12, vertical: 5),
            onPressed: () {
              _controller.saveAndReload();
              Nav.back();
            },
            child: Text(
              'Save',
              style: .new(
                color: const Color.fromARGB(255, 117, 116, 116),
                fontSize: 13.sp,
                fontWeight: .w500,
              ),
            ),
          ),
        ),
      ),
    );

    final body = Column(
      children: [
        BaseAppBar(
          leading: Cs(() {
            return PopScope(
              canPop: !_controller.hasChanged.value,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;
                final res = await _changedDialog();
                if (res == null) return;
                if (!res) {
                  Nav.back();
                  return;
                }
                _controller.saveAndReload();
                Nav.back();
              },
              child: _controller.hasChanged.value
                  ? saveW
                  : const BaseBackButton.black(),
            );
          }),
          center: Text(
            'Application list',
            style: .new(
              color: Colors.black,
              fontSize: 18.sp,
              fontWeight: .w500,
            ),
          ),
          trailing: Padding(padding: .only(right: 5), child: menu),
        ),

        Cs(() {
          if (_controller.mode.value == .none) return const SizedBox();

          return Padding(
            padding: .only(top: 10, left: 10, right: 10),
            child: TextField(
              style: .new(
                fontSize: 14.sp,
                fontWeight: .w500,
                color: Colors.black,
              ),
              textAlignVertical: .center,
              decoration: InputDecoration(
                isCollapsed: true,
                hintText: 'Search applications',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                focusColor: Colors.white,
                hoverColor: Colors.white,
                hintStyle: .new(
                  fontSize: 14.sp,
                  fontWeight: .w500,
                  color: Color(0xFF999999),
                ),
                prefixIconConstraints: .new(maxHeight: 30, minWidth: 30),
                contentPadding: .symmetric(vertical: 10, horizontal: 12.w),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              onChanged: _controller.setSearchText,
            ),
          );
        }),
        const SizedBox(height: 6),

        Cs(() {
          if (_controller.mode.value == .none) return const SizedBox();

          return Row(
            children: [
              12.horizontalSpace,
              Expanded(
                child: Text(
                  _controller.mode.value.label,
                  style: .new(
                    color: Color(0xFF666666),
                    fontSize: 12.sp,
                    fontWeight: .w400,
                  ),
                  maxLines: 2,
                ),
              ),
              6.horizontalSpace,
              Text('Selected ${_controller.selectedPackages.length}'),
              12.horizontalSpace,
            ],
          );
        }),

        Expanded(child: _applicationList.cs),
      ],
    );

    return SystemUI(
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F0F0),
        body: Stack(
          children: [
            body,
            Positioned(
              bottom: 20,
              right: 10,
              child: SafeArea(
                top: false,
                child: Cs(() {
                  final isSellectAll = _controller.isSellectAll;
                  if (_controller.mode.value == .none) return const SizedBox();

                  return InkButton(
                    onPressed: () {
                      if (isSellectAll) {
                        _controller.unSelectAll();
                      } else {
                        _controller.selectAll();
                      }
                    },
                    elevation: 2,
                    backgroundColor: const Color.fromARGB(255, 242, 242, 242),
                    isStadium: true,
                    padding: .symmetric(horizontal: 20, vertical: 10),
                    overlayColor: Color.fromARGB(68, 205, 205, 205),
                    child: Text(
                      _controller.isSellectAll ? 'Cancel' : 'Select All',
                      style: .new(
                        fontSize: 15.sp,
                        fontWeight: .w500,
                        color: Color(0xFF333333),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _applicationList() {
    if (_controller.mode.value == .none) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          spacing: 20.h,
          children: [
            InkButton(
              onPressed: () {
                _controller.mode.value = .blackList;
              },
              padding: .symmetric(horizontal: 50.w, vertical: 14),
              borderRadius: .circular(8),
              backgroundColor: const Color.fromARGB(255, 41, 41, 41),
              overlayColor: const Color.fromARGB(57, 108, 110, 112),
              child: Text(
                ApplicationListMode.blackList.tr,
                style: .new(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: .w500,
                ),
              ),
            ),
            InkButton(
              onPressed: () {
                _controller.mode.value = .whiteList;
              },
              padding: .symmetric(horizontal: 50.w, vertical: 14),
              borderRadius: .circular(8),
              backgroundColor: Colors.blue,
              overlayColor: const Color.fromARGB(57, 39, 94, 187),
              child: Text(
                ApplicationListMode.whiteList.tr,
                style: .new(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: .w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
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

    final top = MediaQuery.paddingOf(context).top;

    return ListView.builder(
      padding: .only(bottom: 50 + top),
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

Future<void> _settings() async {
  showModalBottomSheet(
    context: currentContext,
    shape: RoundedRectangleBorder(
      borderRadius: .vertical(top: .circular(20.r)),
    ),
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (context) {
      return _Settings();
    },
  );
}

class _Settings extends StatefulWidget {
  const new();

  @override
  State<_Settings> createState() => __SettingsState();
}

class __SettingsState extends State<_Settings> {
  late final ApplicationListController controller = getType();

  @override
  Widget build(BuildContext context) {
    final modeText = Text(
      'Mode',
      style: .new(color: Colors.black, fontSize: 16.sp, fontWeight: .w500),
    );
    final typeText = Text(
      'App Type',
      style: .new(color: Colors.black, fontSize: 16.sp, fontWeight: .w500),
    );

    final title = BaseAppBar(
      removeTop: false,
      color: Colors.transparent,
      center: Text(
        'Settings',
        style: .new(fontSize: 18.sp, fontWeight: .w500, color: Colors.black),
      ),
    );

    final modeW = Cs(() {
      final value = controller.mode.value;
      return DefaultTabController(
        initialIndex: value.index,
        length: ApplicationListMode.values.length,
        child: TabBar(
          labelStyle: .new(
            color: Color.fromARGB(255, 249, 247, 247),
            fontSize: 13.sp,
            fontWeight: .w500,
          ),
          unselectedLabelStyle: .new(
            color: Color(0xFF666666),
            fontSize: 13.sp,
            fontWeight: .w500,
          ),
          padding: .symmetric(horizontal: 6.w, vertical: 6),
          labelPadding: .symmetric(vertical: 5, horizontal: 10),
          isScrollable: true,
          tabAlignment: .start,
          dividerHeight: 0,
          indicatorSize: .tab,
          indicator: ShapeDecoration(
            shape: StadiumBorder(),
            color: const Color.fromARGB(255, 87, 138, 255),
          ),
          overlayColor: WidgetStatePropertyAll(Colors.transparent),
          tabs: ApplicationListMode.values.map((e) {
            return Text(e.tr);
          }).toList(),
          onTap: (value) {
            controller.mode.value = .fromJson(value);
          },
        ),
      );
    });

    final systemAppW = Cs(() {
      final showSystemApp = controller.showSystemApps.value;

      return InkButton(
        onPressed: () {
          controller.setShowSystemApps(!showSystemApp);
        },
        padding: .symmetric(horizontal: 20, vertical: 8),
        borderRadius: .circular(8),
        backgroundColor: showSystemApp
            ? const Color.fromARGB(255, 83, 120, 221)
            : Colors.transparent,
        overlayColor: const Color.fromARGB(82, 123, 158, 238),
        side: showSystemApp
            ? null
            : .new(
                color: const Color.fromARGB(255, 223, 223, 223),
                width: 1.4.r,
              ),

        child: Text(
          'System Apps',
          style: .new(
            color: showSystemApp ? Colors.white : Colors.black,
            fontSize: 14.sp,
            fontWeight: .w500,
          ),
        ),
      );
    });

    final netAppsW = Cs(() {
      final showNoInternetApps = controller.showNoInternetApps.value;

      return InkButton(
        onPressed: () {
          controller.showNoInternetApps.value = !showNoInternetApps;
        },
        padding: .symmetric(horizontal: 20, vertical: 8),
        borderRadius: .circular(8),
        backgroundColor: showNoInternetApps
            ? const Color.fromARGB(255, 83, 120, 221)
            : Colors.transparent,
        overlayColor: const Color.fromARGB(82, 123, 158, 238),
        side: showNoInternetApps
            ? null
            : .new(
                color: const Color.fromARGB(255, 223, 223, 223),
                width: 1.4.r,
              ),
        child: Text(
          'No Network Apps',
          style: .new(
            color: showNoInternetApps ? Colors.white : Colors.black,
            fontSize: 14.sp,
            fontWeight: .w500,
          ),
        ),
      );
    });

    Widget content = Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        title,
        15.verticalSpace,
        modeText,
        modeW,
        12.verticalSpace,
        typeText,
        12.verticalSpace,
        Row(spacing: 20.w, children: [systemAppW, netAppsW]),
      ],
    );

    content = Container(
      constraints: .new(minHeight: 300.h),
      padding: .symmetric(horizontal: 10.w),
      child: content,
    );

    return content;
  }
}

Future<bool?> _changedDialog() async {
  final res = await showCenterDialog(currentContext, _ChangeDialog());
  if (res is bool) return res;
  return null;
}

class _ChangeDialog extends StatefulWidget {
  const new();

  @override
  State<_ChangeDialog> createState() => __ChangeDialogState();
}

class __ChangeDialogState extends State<_ChangeDialog> {
  @override
  Widget build(BuildContext context) {
    final titleW = BaseAppBar(
      removeTop: false,
      center: Text(
        'Apply Modified Configuration?',
        style: .new(color: Colors.black, fontSize: 15.sp, fontWeight: .w500),
      ),
    );

    final content = Text(
      'Do you want to apply the modified configuration now?',
      textAlign: .center,
      style: .new(
        color: Color.fromARGB(255, 118, 116, 116),
        fontSize: 13.sp,
        fontWeight: .w400,
      ),
    );

    final cancelW = InkButton(
      backgroundColor: Colors.transparent,
      padding: .symmetric(vertical: 14),
      overlayColor: const Color.fromARGB(41, 166, 166, 166),
      borderRadius: .zero,
      onPressed: () {
        Nav.back(false);
      },
      child: Center(
        child: Text(
          'Cancel',
          style: .new(
            color: const Color.fromARGB(255, 139, 139, 139),
            fontSize: 14.sp,
            fontWeight: .w400,
          ),
        ),
      ),
    );

    final saveW = InkButton(
      backgroundColor: Colors.transparent,
      padding: .symmetric(vertical: 14),
      overlayColor: const Color.fromARGB(52, 96, 147, 248),
      borderRadius: .zero,
      onPressed: () {
        Nav.back(true);
      },
      child: Center(
        child: Text(
          'Save',
          style: .new(
            color: const Color.fromARGB(255, 43, 126, 244),
            fontSize: 14.sp,
            fontWeight: .w400,
          ),
        ),
      ),
    );

    Widget body = Column(
      mainAxisSize: .min,
      children: [titleW, 12.verticalSpace, content, 32.verticalSpace],
    );

    body = Container(
      padding: .symmetric(horizontal: 20.w, vertical: 20.h),
      child: body,
    );

    body = Column(
      mainAxisSize: .min,
      children: [
        body,

        Container(
          color: const Color.fromARGB(108, 213, 213, 213),
          height: 0.5.r,
          width: double.infinity,
        ),

        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(child: cancelW),
              Container(
                color: const Color.fromARGB(108, 213, 213, 213),
                width: 0.5.r,
              ),
              Expanded(child: saveW),
            ],
          ),
        ),
      ],
    );

    body = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: .circular(20),
      ),
      clipBehavior: .hardEdge,
      margin: .symmetric(horizontal: 24.w),
      child: body,
    );
    body = Material(color: Colors.transparent, child: body);

    return body;
  }
}
