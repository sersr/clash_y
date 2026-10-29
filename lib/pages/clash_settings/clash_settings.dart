import 'package:clashy/pages/home/widget/setting_item.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:material_ui/material_ui.dart';

class ClashSettings extends StatefulWidget {
  const new({super.key});

  @override
  State<ClashSettings> createState() => _ClashSettingsState();
}

class _ClashSettingsState extends State<ClashSettings> {
  @override
  Widget build(BuildContext context) {
    final modeW = Cs(() {
      final value = SettingsHive.mode.value;
      return SettingItem(
        label: "Mode",
        child: DefaultTabController(
          initialIndex: value.index,
          length: SettingMode.values.length,
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
            labelPadding: .symmetric(vertical: 10, horizontal: 10),
            isScrollable: true,
            tabAlignment: .start,
            dividerHeight: 0,
            indicatorSize: .tab,
            indicator: ShapeDecoration(
              shape: StadiumBorder(),
              color: const Color.fromARGB(255, 87, 138, 255),
            ),
            overlayColor: WidgetStatePropertyAll(Colors.transparent),
            tabs: SettingMode.values.map((e) {
              return Text(e.showName);
            }).toList(),
            onTap: (value) {
              SettingsHive.mode.value = SettingMode.fromJson(value);
            },
          ),
        ),
      );
    });

    final tunEnabled = Cs(
      () => SettingItem(
        label: "Tun",
        enabled: SettingsHive.tunEnabled.value,
        onTap: () {
          SettingsHive.tunEnabled.value = !SettingsHive.tunEnabled.value;
        },
      ),
    );
    final ipv6Enabled = Cs(
      () => SettingItem(
        label: "Ipv6",
        enabled: SettingsHive.ipv6.value,
        onTap: () {
          SettingsHive.ipv6.value = !SettingsHive.ipv6.value;
        },
      ),
    );

    final tunStack = Cs(() {
      final value = SettingsHive.tunStack.value;
      return SettingItem(
        label: "Stack Mode",
        child: DefaultTabController(
          initialIndex: value.index,
          length: ClashTunStack.values.length,
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
            labelPadding: .symmetric(vertical: 10, horizontal: 10),
            isScrollable: true,
            tabAlignment: .start,
            dividerHeight: 0,
            indicatorSize: .tab,
            indicator: ShapeDecoration(
              shape: StadiumBorder(),
              color: const Color.fromARGB(255, 87, 138, 255),
            ),
            overlayColor: WidgetStatePropertyAll(Colors.transparent),
            tabs: ClashTunStack.values.map((e) {
              return Text(e.showName);
            }).toList(),
            onTap: (value) {
              SettingsHive.tunStack.value = ClashTunStack.fromJson(value);
            },
          ),
        ),
      );
    });

    final body = ListView(
      children: [
        SettingDecoration(
          child: Column(
            children: [
              Cs(() {
                final mixedPort = SettingsHive.mixedProt.value;
                return SettingItem(
                  label: "Mixed Port",
                  value: '$mixedPort',
                  onTap: () async {
                    final port = await _inputEdit("Mixed Port", '$mixedPort');
                    if (int.tryParse(port) case var port?) {
                      SettingsHive.mixedProt.value = port;
                    }
                  },
                );
              }),
              SettingDiv(),
              Cs(() {
                final value = SettingsHive.allowLan.value;
                return SettingItem(
                  label: "Allow Lan",
                  enabled: value,
                  onTap: () => SettingsHive.allowLan.value = !value,
                );
              }),
              SettingDiv(),
              ipv6Enabled,
              SettingDiv(),
              modeW,
            ],
          ),
        ),
        12.verticalSpace,
        SettingDecoration(
          child: Column(children: [tunEnabled, SettingDiv(), tunStack]),
        ),
      ],
    );

    final appbar = BaseAppBar(
      leading: const BaseBackClosedButton.black(),
      center: Text(
        "Clash Settings",
        style: .new(
          color: Color(0xFF333333),
          fontSize: 18.sp,
          fontWeight: .w400,
        ),
      ),
    );

    return SystemUI(
      child: Scaffold(
        backgroundColor: .fromARGB(255, 245, 245, 245),
        body: Column(
          children: [
            appbar,
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

Future<String> _inputEdit(String label, String initValue) async {
  final res = await showCenterDialog(
    currentContext!,
    alignment: .new(0, -0.3),
    _Dialog(initValue: initValue),
  );

  if (res case String v) {
    return v;
  }
  return '';
}

class _Dialog extends StatefulWidget {
  const new({required this.initValue});
  final String initValue;
  @override
  State<_Dialog> createState() => __DialogState();
}

class __DialogState extends State<_Dialog> {
  final editController = TextEditingController();

  @override
  void initState() {
    editController.text = widget.initValue;
    super.initState();
  }

  @override
  void dispose() {
    editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = ShapedInputBorder(
      shape: RoundedRectangleBorder(borderRadius: .circular(8)),
      borderSide: .new(
        color: const Color.fromARGB(255, 23, 145, 245),
        width: 2.r,
      ),
    );
    final borderNone = ShapedInputBorder(
      shape: RoundedRectangleBorder(borderRadius: .circular(8)),
      borderSide: .new(
        color: const Color.fromARGB(255, 208, 208, 208),
        width: 2.r,
      ),
    );

    final editW = TextField(
      controller: editController,
      style: .new(color: Color(0xFF333333), fontSize: 14.sp, fontWeight: .w400),
      inputFormatters: const [IntPrefixFormater(prefix: '', iPrefix: '')],
      decoration: .new(
        isCollapsed: true,
        hintText: '',
        contentPadding: .symmetric(vertical: 16, horizontal: 6),
        border: .none,
        focusedBorder: border,
        disabledBorder: borderNone,
        enabledBorder: borderNone,
      ),
    );

    final title = BaseAppBar(
      removeTop: false,
      center: Text(
        'Mixed Port',
        style: .new(
          fontSize: 18.sp,
          fontWeight: .w500,
          color: Color(0xFF333333),
        ),
      ),
    );

    final cancleW = InkButton(
      onPressed: () {
        Nav.back();
      },
      padding: .symmetric(vertical: 14),
      backgroundColor: Colors.transparent,
      side: .new(color: Color.fromARGB(59, 153, 153, 153), width: 1.2.r),
      borderRadius: .circular(12),
      overlayColor: const Color.fromARGB(87, 191, 191, 191),
      child: Center(
        child: Text(
          "Cancel",
          style: .new(
            fontSize: 13.sp,
            fontWeight: .w400,
            color: Color.fromARGB(255, 77, 76, 76),
          ),
        ),
      ),
    );

    final confirmW = InkButton(
      onPressed: () {
        Nav.back(editController.text.trim());
      },
      padding: .symmetric(vertical: 14),
      backgroundColor: const Color.fromARGB(255, 17, 130, 251),
      borderRadius: .circular(12),
      overlayColor: const Color.fromARGB(42, 253, 253, 253),
      child: Center(
        child: Text(
          "Confirm",
          style: .new(
            fontSize: 13.sp,
            fontWeight: .w400,
            color: Color.fromARGB(255, 251, 248, 248),
          ),
        ),
      ),
    );

    Widget body = Column(
      mainAxisSize: .min,
      children: [
        title,
        22.verticalSpace,
        editW,
        32.verticalSpace,
        Row(
          spacing: 20,
          children: [
            Expanded(child: cancleW),
            Expanded(child: confirmW),
          ],
        ),
        14.verticalSpace,
      ],
    );

    body = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: .circular(16.r),
      ),
      margin: .symmetric(horizontal: 34.w),
      padding: .symmetric(horizontal: 14.w),
      child: body,
    );

    body = Material(color: Colors.transparent, child: body);

    return body;
  }
}
