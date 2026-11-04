import 'package:clashy/pages/home/widget/profile_item.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:material_ui/material_ui.dart';

import '../controller/configs_controller.dart';

class ClashProfiles extends StatefulWidget {
  const new({super.key});

  @override
  State<ClashProfiles> createState() => _ClashProfilesState();
}

class _ClashProfilesState extends State<ClashProfiles> {
  late ConfigsController clashConfigNotifier = getType();

  late TextEditingController textEditingController;
  late FocusNode focusNode;
  late ScrollController controller;

  @override
  void initState() {
    super.initState();
    textEditingController = TextEditingController();
    focusNode = FocusNode();
    controller = ScrollController();
  }

  @override
  Widget build(BuildContext context) {
    final appbar = BaseAppBar(
      center: Text(
        "Profiles",
        style: .new(fontSize: 18.sp, fontWeight: .w500),
      ),
      trailing: InkButton(
        onPressed: () {
          _newProfile();
        },
        backgroundColor: Colors.transparent,
        shape: CircleBorder(),
        padding: .all(9.r),
        overlayColor: const Color(0x3AB4AEF9),
        child: Icon(Icons.add, size: 24.sp),
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      body: Column(
        children: [
          appbar,
          Expanded(child: _body.cs),
        ],
      ),
    );
  }

  Widget _body() {
    final profiles = clashConfigNotifier.profiles.values.toList();

    final body = SliverList.builder(
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        final item = profiles[index];
        return ProfileItem(item: item);
      },
    );

    return Refresh(
      isEmpty: profiles.isEmpty,
      emptyWidget: Center(
        child: Text(
          'Empty',
          style: .new(
            color: Color(0xFF333333),
            fontSize: 15.sp,
            fontWeight: .w500,
          ),
        ),
      ),
      slivers: [body],
    );
  }

  Future<void> _newProfile() async {
    final res = await updateOrCreateProfile(false, null);

    if (res != null) {
      await clashConfigNotifier.addNewConfigUrl(
        res.url,
        res.name,
        res.interval,
      );
    }
  }
}

Future<({String url, String name, int? interval})?> updateOrCreateProfile(
  bool isEdit,
  Profile? profile,
) async {
  final res = await showCenterDialog(
    currentContext,
    _NewConfig(isEdit: isEdit, profile: profile),
  );

  if (res case (url: String _, name: String _, interval: int? _)) {
    return res;
  }
  return null;
}

class _NewConfig extends StatefulWidget {
  const new({required this.isEdit, required this.profile});
  final bool isEdit;
  final Profile? profile;
  @override
  State<_NewConfig> createState() => _NewConfigState();
}

class _NewConfigState extends State<_NewConfig> {
  final editName = TextEditingController();
  final editUrl = TextEditingController();
  final editInterval = TextEditingController();

  @override
  void initState() {
    editName.text = widget.profile?.name ?? '';
    editUrl.text = widget.profile?.url ?? '';
    editInterval.text = widget.profile?.updateInterval?.toString() ?? '';
    super.initState();
  }

  @override
  void dispose() {
    editName.dispose();
    editUrl.dispose();
    editInterval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = Text(
      widget.isEdit ? "Update Profile" : "New Profile",
      style: .new(fontSize: 15.sp, fontWeight: .w400),
    );

    final editNameW = TextField(
      controller: editName,
      style: .new(
        color: CT.color(.new(0xFF333333)).color,
        fontSize: 14.sp,
        fontWeight: .w400,
      ),
      textInputAction: .next,
      decoration: .new(
        isCollapsed: true,
        contentPadding: .symmetric(vertical: 16.h, horizontal: 8.w),
        hintText: widget.profile?.rawName ?? "Profile name (Optional)",
        hintStyle: .new(
          color: CT(
            light: .fromARGB(255, 160, 160, 160),
            dark: .fromARGB(100, 100, 100, 100),
          ).color,
          fontSize: 14.sp,
          fontWeight: .w400,
        ),
        border: .none,
        focusedBorder: ShapedInputBorder(
          borderSide: .new(
            color: CT.textFieldBorderColorFocus.color,
            width: 2.r,
          ),
          shape: RoundedRectangleBorder(borderRadius: .circular(8.r)),
        ),
        enabledBorder: ShapedInputBorder(
          borderSide: .new(color: CT.textFieldBorderColor.color, width: 1.6.r),
          shape: RoundedRectangleBorder(borderRadius: .circular(8.r)),
        ),
      ),
    );

    final editUrlW = TextField(
      controller: editUrl,
      style: .new(
        color: CT.color(.new(0xFF333333)).color,
        fontSize: 14.sp,
        fontWeight: .w400,
      ),
      textInputAction: .next,
      decoration: .new(
        isCollapsed: true,
        contentPadding: .symmetric(vertical: 16.h, horizontal: 8.w),
        hintText: "Subscribe URL (Required)",
        hintStyle: .new(
          color: CT(
            light: .fromARGB(255, 160, 160, 160),
            dark: .fromARGB(100, 100, 100, 100),
          ).color,
          fontSize: 14.sp,
          fontWeight: .w400,
        ),
        border: .none,
        focusedBorder: ShapedInputBorder(
          borderSide: .new(
            color: CT.textFieldBorderColorFocus.color,
            width: 2.r,
          ),
          shape: RoundedRectangleBorder(borderRadius: .circular(8.r)),
        ),
        enabledBorder: ShapedInputBorder(
          borderSide: .new(color: CT.textFieldBorderColor.color, width: 1.6.r),
          shape: RoundedRectangleBorder(borderRadius: .circular(8.r)),
        ),
      ),
    );
    final editIntervalW = TextField(
      controller: editInterval,
      style: .new(
        color: CT.color(.new(0xFF333333)).color,
        fontSize: 14.sp,
        fontWeight: .w400,
      ),
      textInputAction: .done,
      keyboardType: .number,
      inputFormatters: [const IntPrefixFormater(prefix: '', iPrefix: '')],
      decoration: .new(
        isCollapsed: true,
        contentPadding: .symmetric(vertical: 16.h, horizontal: 8.w),
        hintText: "Update interval (Minutes)",
        hintStyle: .new(
          color: CT(
            light: .fromARGB(255, 160, 160, 160),
            dark: .fromARGB(100, 100, 100, 100),
          ).color,
          fontSize: 14.sp,
          fontWeight: .w400,
        ),
        border: .none,
        focusedBorder: ShapedInputBorder(
          borderSide: .new(
            color: CT.textFieldBorderColorFocus.color,
            width: 2.r,
          ),
          shape: RoundedRectangleBorder(borderRadius: .circular(8.r)),
        ),
        enabledBorder: ShapedInputBorder(
          borderSide: .new(color: CT.textFieldBorderColor.color, width: 1.6.r),
          shape: RoundedRectangleBorder(borderRadius: .circular(8.r)),
        ),
      ),
    );

    final confirmW = InkButton(
      onPressed: () {
        final name = editName.text.trim();
        final url = editUrl.text.trim();
        final interval = editInterval.text.trim();

        if (url.isEmpty) {
          showMsg("Please input Subscribe URL.");
          return;
        }
        final uri = Uri.tryParse(url);

        if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
          showMsg("$url is not the correct URL.");
          return;
        }
        int? intervalM;

        if (interval.isNotEmpty) {
          intervalM = int.tryParse(interval);
        }

        Nav.back((url: url, name: name, interval: intervalM));
      },
      padding: .symmetric(vertical: 10.h, horizontal: 32.w),
      overlayColor: CT(
        light: const Color(0x35FFFFFF),
        dark: const Color(0x35FFFFFF),
      ).color,
      borderRadius: .circular(12.r),
      backgroundColor: CT(light: Colors.blue, dark: Colors.blue).color,

      child: Text(
        widget.isEdit ? 'Update' : "Add",
        style: .new(
          color: CT(light: .new(0xFFFFFFFF), dark: .new(0xFF333333)).color,
        ),
      ),
    );
    final cancelW = InkButton(
      onPressed: () {
        Nav.back();
      },
      padding: .symmetric(vertical: 10.h, horizontal: 32.w),
      overlayColor: CT(
        light: const Color(0x35A0A0A0),
        dark: const Color(0x35A0A0A0),
      ).color,
      borderRadius: .circular(12.r),
      backgroundColor: CT(
        light: Colors.transparent,
        dark: Colors.transparent,
      ).color,

      side: .new(
        color: CT(
          light: const Color(0x488A8A8A),
          dark: const Color(0x488A8A8A),
        ).color,
        width: 1.5.r,
      ),
      child: Text(
        "Cancel",
        style: .new(
          color: CT(light: .new(0xFF3A3A3A), dark: .new(0xFF3A3A3A)).color,
        ),
      ),
    );

    Widget body = Column(
      mainAxisSize: .min,
      children: [
        title,
        12.verticalSpace,
        editNameW,
        12.verticalSpace,
        editUrlW,
        12.verticalSpace,
        editIntervalW,

        32.verticalSpace,
        Row(
          spacing: 20.w,
          children: [
            Expanded(child: cancelW),
            Expanded(child: confirmW),
          ],
        ),
      ],
    );

    body = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: .circular(12.r),
      ),
      padding: .symmetric(vertical: 14.h, horizontal: 14.w),
      margin: .symmetric(horizontal: 32.w),
      child: body,
    );

    return Material(color: Colors.transparent, child: body);
  }
}
