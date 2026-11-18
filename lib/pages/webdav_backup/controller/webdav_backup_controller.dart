import 'dart:async';
import 'dart:io';

import 'package:clashy/event/clash_event.dart';
import 'package:common/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart' as share;

class WebDavBackupController with NopLifecycle {
  final _service = WebDavBackupService();

  final urlController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final remotePathController = TextEditingController(text: '/clashy-backup');

  final autoSync = false.val;
  final busy = false.val;
  final status = ''.val;

  Timer? _dailyTimer;
  AppLifecycleListener? _lifecycleListener;

  @override
  void nopInit() {
    super.nopInit();
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(_maybeAutoSync()),
    );
    _loadSettings();
  }

  void _loadSettings() {
    try {
      final settings = _service.loadSettings();
      urlController.text = settings.url;
      usernameController.text = settings.username;
      remotePathController.text = settings.remotePath;
      autoSync.value = settings.autoSync;
      _configureDailySync();
      if (settings.autoSync) unawaited(_maybeAutoSync());
    } catch (error, stackTrace) {
      Log.e('Load WebDAV backup settings failed: $error\n$stackTrace');
      status.value = 'Could not load WebDAV settings: $error';
    }
  }

  Future<void> saveSettings() async {
    try {
      await _persistSettings();
      status.value = 'Settings saved.';
    } catch (error, stackTrace) {
      Log.e('Save WebDAV backup settings failed: $error\n$stackTrace');
      status.value = 'Could not save settings: $error';
    }
  }

  Future<void> toggleAutoSync() async {
    final previous = autoSync.value;
    autoSync.value = !previous;
    try {
      await _persistSettings();
      _configureDailySync();
      status.value = autoSync.value
          ? 'Automatic sync enabled.'
          : 'Automatic sync disabled.';
      if (autoSync.value) unawaited(_maybeAutoSync());
    } catch (error, stackTrace) {
      autoSync.value = previous;
      Log.e('Update WebDAV automatic sync failed: $error\n$stackTrace');
      status.value = 'Could not update automatic sync: $error';
    }
  }

  Future<void> testConnection() async {
    if (busy.value) return;
    busy.value = true;
    status.value = 'Testing WebDAV connection...';
    try {
      await _persistSettings();
      await _service.testConnection();
      status.value = 'WebDAV connection successful.';
    } catch (error, stackTrace) {
      Log.e('Test WebDAV connection failed: $error\n$stackTrace');
      status.value = 'Connection failed: $error';
    } finally {
      busy.value = false;
    }
  }

  Future<void> synchronize() => _runSync();

  Future<void> saveArchiveExternally() async {
    if (busy.value) return;
    busy.value = true;
    status.value = 'Preparing ZIP backup...';
    Directory? temporaryDirectory;
    try {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'clashy-backup-',
      );
      final archive = await _service.exportArchive(
        '${temporaryDirectory.path}/clashy-backup.zip',
      );
      final bytes = await archive.readAsBytes();
      await temporaryDirectory.delete(recursive: true);
      temporaryDirectory = null;
      final savedUri = await FilePicker.saveFile(
        fileName: 'clashy-backup.zip',
        bytes: bytes,
        mimeType: 'application/zip',
        dialogTitle: 'Save Clashy backup',
      );
      status.value = savedUri == null
          ? 'ZIP backup save cancelled.'
          : 'ZIP backup saved to $savedUri';
    } catch (error, stackTrace) {
      Log.e('Save ZIP backup externally failed: $error\n$stackTrace');
      status.value = 'Could not save ZIP backup externally: $error';
    } finally {
      if (temporaryDirectory != null && await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
      busy.value = false;
    }
  }

  Future<void> exportArchive() async {
    if (busy.value) return;
    if (Platform.isAndroid || Platform.isIOS) {
      busy.value = true;
      status.value = 'Preparing ZIP backup...';
      try {
        final directory = await Directory.systemTemp.createTemp(
          'clashy-backup-',
        );
        final archive = await _service.exportArchive(
          '${directory.path}/clashy-backup.zip',
        );
        await share.SharePlus.instance.share(
          share.ShareParams(
            title: 'Clashy backup',
            files: [XFile(archive.path, mimeType: 'application/zip')],
          ),
        );
        status.value =
            'ZIP backup ready. Choose a destination in the share sheet.';
      } catch (error, stackTrace) {
        Log.e('Export ZIP backup failed: $error\n$stackTrace');
        status.value = 'Could not export ZIP backup: $error';
      } finally {
        busy.value = false;
      }
      return;
    }

    final location = await getSaveLocation(
      suggestedName: 'clashy-backup.zip',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ZIP archive', extensions: ['zip']),
      ],
      confirmButtonText: 'Save',
    );
    if (location == null) return;

    busy.value = true;
    status.value = 'Creating ZIP backup...';
    try {
      await _service.exportArchive(location.path);
      status.value = 'ZIP backup saved to ${location.path}';
    } catch (error, stackTrace) {
      Log.e('Export ZIP backup failed: $error\n$stackTrace');
      status.value = 'Could not export ZIP backup: $error';
    } finally {
      busy.value = false;
    }
  }

  Future<void> restoreArchive() async {
    if (busy.value) return;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ZIP archive', extensions: ['zip']),
      ],
    );
    if (file == null) return;
    final context = currentContext;
    if (!context.mounted) return;
    final confirmed = await showCenterDialog<bool>(
      context,
      _RestoreConfirmationDialog(fileName: file.name),
    );
    if (confirmed != true) return;

    busy.value = true;
    status.value = 'Restoring ZIP backup...';
    try {
      await _service.restoreArchive(file.path);
      getType<ClashEvent>().reloadCurrentConfig();
      status.value = 'ZIP backup restored.';
    } catch (error, stackTrace) {
      Log.e('Restore ZIP backup failed: $error\n$stackTrace');
      status.value = 'Could not restore ZIP backup: $error';
    } finally {
      busy.value = false;
    }
  }

  Future<void> _runSync({bool automatic = false}) async {
    if (busy.value) return;
    busy.value = true;
    status.value = automatic ? 'Running automatic sync...' : 'Syncing...';
    try {
      await _persistSettings();
      final result = await _service.synchronize();
      if (result.restored) {
        getType<ClashEvent>().reloadCurrentConfig();
      }
      status.value = result.message;
    } catch (error, stackTrace) {
      Log.e('WebDAV backup sync failed: $error\n$stackTrace');
      status.value = '${automatic ? 'Automatic sync' : 'Sync'} failed: $error';
    } finally {
      busy.value = false;
    }
  }

  Future<void> _maybeAutoSync() async {
    if (!autoSync.value || busy.value) return;
    try {
      await _runSync(automatic: true);
    } catch (error, stackTrace) {
      Log.e('Check automatic WebDAV sync failed: $error\n$stackTrace');
      status.value = 'Could not check automatic sync: $error';
    }
  }

  Future<void> _persistSettings() async {
    await _service.saveSettings(
      WebDavBackupSettings(
        url: urlController.text,
        username: usernameController.text,
        remotePath: remotePathController.text,
        autoSync: autoSync.value,
      ),
      password: passwordController.text,
    );
    passwordController.clear();
  }

  void _configureDailySync() {
    _dailyTimer?.cancel();
    _dailyTimer = null;
    if (autoSync.value) {
      _dailyTimer = Timer.periodic(
        const Duration(days: 1),
        (_) => unawaited(_maybeAutoSync()),
      );
    }
  }

  @override
  void nopDispose() {
    _dailyTimer?.cancel();
    _lifecycleListener?.dispose();
    urlController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    remotePathController.dispose();
    super.nopDispose();
  }
}

class _RestoreConfirmationDialog extends StatelessWidget {
  const _RestoreConfirmationDialog({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Restore ZIP backup?',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Text(
              'Restoring "$fileName" will replace the current app data and settings.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Nav.back(false),
                    child: const Text('Cancel'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Nav.back(true),
                    child: const Text('Restore'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
