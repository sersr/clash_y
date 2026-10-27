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
                  onTap: () {},
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
