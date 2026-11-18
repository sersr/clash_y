import 'package:flutter/foundation.dart';
import 'package:clashy/pages/home/widget/setting_item.dart';
import 'package:clashy/pages/webdav_backup/controller/webdav_backup_controller.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:material_ui/material_ui.dart';

class WebDavBackupPage extends StatefulWidget {
  const WebDavBackupPage({super.key});

  @override
  State<WebDavBackupPage> createState() => _WebDavBackupPageState();
}

class _WebDavBackupPageState extends State<WebDavBackupPage> {
  late final controller = getType<WebDavBackupController>();

  @override
  Widget build(BuildContext context) {
    controller;

    final body = ListView(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      children: [
        SettingDecoration(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
            child: Column(
              children: [
                _field(
                  controller: controller.urlController,
                  label: 'WebDAV URL',
                  hint: 'https://example.com/remote.php/dav/files/user',
                  keyboardType: TextInputType.url,
                ),
                _field(
                  controller: controller.usernameController,
                  label: 'Username',
                  keyboardType: TextInputType.text,
                ),
                _field(
                  controller: controller.passwordController,
                  label: 'Password',
                  obscureText: true,
                ),
                _field(
                  controller: controller.remotePathController,
                  label: 'Remote folder',
                  hint: '/clashy-backup',
                ),
              ],
            ),
          ),
        ),
        12.verticalSpace,
        SettingDecoration(
          child: Column(
            children: [
              Cs(
                () => SettingItem(
                  label: 'Automatic daily sync',
                  enabled: controller.autoSync.value,
                  onTap: controller.toggleAutoSync,
                ),
              ),
              const SettingDiv(),
              SettingItem(
                label: 'Save settings',
                onTap: controller.saveSettings,
                child: const SizedBox(),
              ),
              const SettingDiv(),
              SettingItem(
                label: 'Test connection',
                onTap: controller.testConnection,
                child: const SizedBox(),
              ),
              const SettingDiv(),
              SettingItem(
                label: 'Sync now',
                onTap: controller.synchronize,
                child: const SizedBox(),
              ),
              const SettingDiv(),
              SettingItem(
                label: 'Export ZIP backup',
                onTap: controller.exportArchive,
                child: const SizedBox(),
              ),
              if (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS) ...[
                const SettingDiv(),
                SettingItem(
                  label: 'Save ZIP externally',
                  onTap: controller.saveArchiveExternally,
                  child: const SizedBox(),
                ),
              ],
              const SettingDiv(),
              SettingItem(
                label: 'Restore ZIP backup',
                onTap: controller.restoreArchive,
                child: const SizedBox(),
              ),
            ],
          ),
        ),
        12.verticalSpace,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Text(
            'ZIP backups are not encrypted and may contain private configuration data. '
            'WebDAV passwords are stored in secure storage; authenticated connections require HTTPS.',
            style: TextStyle(color: const Color(0xFF777777), fontSize: 12.sp),
          ),
        ),
        12.verticalSpace,
        Cs(() {
          final message = controller.status.value;
          final busy = controller.busy.value;
          if (message.isEmpty && !busy) return const SizedBox.shrink();
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              children: [
                if (busy) ...[
                  SizedBox(
                    width: 16.w,
                    height: 16.w,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  8.horizontalSpace,
                ],
                Expanded(child: Text(message)),
              ],
            ),
          );
        }),
      ],
    );

    return SystemUI(
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F0F0),
        body: Column(
          children: [
            BaseAppBar(
              leading: const BaseBackClosedButton.black(),
              center: Text(
                'WebDAV Backup',
                style: TextStyle(
                  color: const Color(0xFF333333),
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
