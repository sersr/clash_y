import 'package:clashy/pages/clash_settings/profile_script.dart';
import 'package:common/common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_nop/router.dart';
import 'package:nop/nop.dart';

import '../pages/application_list/application_list.dart';
import '../pages/clash_settings/clash_settings.dart';
import '../pages/clash_settings/script_edit.dart';
import '../pages/clash_settings/script_select.dart';
import '../pages/home/home.dart';
import '../pages/webdav_backup/webdav_backup.dart';

part 'routes.g.dart';

@RouterMain(
  page: Home,
  pages: [
    RouterPage(name: 'applicationList', page: ApplicationListPage),
    RouterPage(page: ProfileScriptPage),
    .new(page: ScriptEdit),
    .new(page: ScriptSelect),
    .new(page: ClashSettings),
    .new(page: WebDavBackupPage),
  ],
)
NRouter get router => Routes.router;
