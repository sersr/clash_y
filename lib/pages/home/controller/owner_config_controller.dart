import 'package:common/common.dart';

final class OwnerConfigController {
  final baseConfig = BaseConfig.baseConfig;
  bool get tunEnable => baseConfig.value.tun.enable;

  set tunEnable(bool v) {
    if (v == tunEnable) return;
    baseConfig.value = baseConfig.value.copyWith(
      tun: baseConfig.value.tun.copyWith(enable: v),
    );
  }
}
