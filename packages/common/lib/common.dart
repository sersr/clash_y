import 'package:material_ui/material_ui.dart';
import 'package:ui_widgets/ui_widgets.dart';

export 'package:overlays/overlays.dart'
    show Overlays, PopMenuButtonState, PopMenuButton;
export 'package:ui_widgets/ui_widgets.dart';

export 'src/base_config_yaml.dart';
export 'src/constants.dart';
export 'src/data/_g.dart';
export 'src/ext/color_ext.dart';
export 'src/ext/duration_ext.dart';

/// src
export 'src/fs.dart';
export 'src/global.dart';
export 'src/hive.dart';
export 'src/macos/proxy.dart';

///
export 'src/storage.dart';
export 'src/utils/copy.dart';

/// utils
export 'src/utils/date_format.dart';
export 'src/utils/input_filter.dart';
export 'src/utils/local_notication.dart';
export 'src/utils/number_format.dart';
export 'src/utils/platform.dart';
export 'src/utils/yaml.dart';
export 'src/utils/equal.dart';

/// widget
export 'src/widget/base_dialog.dart';

BuildContext get currentContext => GlobalContext.context;
