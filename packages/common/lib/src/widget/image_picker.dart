import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_picker/image_picker.dart';

import '../ext/screen_ext.dart';
import '../navigator_observer.dart';
import '../utils/permission.dart';
import 'buttons.dart';

abstract class ImagePickerUtils {
  static final impagePicker = ImagePicker();
  static Future<String?> pickImage({
    bool isGallery = true,
    CameraDevice camera = CameraDevice.rear,
  }) async {
    if (!isGallery) {
      final granted = await PermissionChecker.requireCamera();
      if (!granted) {
        // final confirm = await showConfirm(context, 'camera_per_dialog'.tr);
        // if (!confirm) return null;
        // await PermissionChecker.openSettings();
        return null;
      }
    }

    final image = await impagePicker.pickImage(
      imageQuality: 88,
      preferredCameraDevice: camera,
      source: isGallery ? ImageSource.gallery : ImageSource.camera,
    );

    return image?.path;
  }

  static Future<String?> showImagePicker(BuildContext context) async {
    final isGallery = await showModalBottomSheet(
      context: context,
      clipBehavior: Clip.hardEdge,
      builder: (context) {
        return const _ImagePickerWidget();
      },
    );

    return switch (isGallery) {
      bool isGallery => pickImage(isGallery: isGallery),
      _ => null,
    };
  }

  static Future<String> savePicture(Uint8List bytes, String name) async {
    final result = await ImageGallerySaver.saveImage(bytes, name: name);
    if (result case {'filePath': String filePath}) {
      return filePath;
    }
    return '';
  }
}

class _ImagePickerWidget extends StatelessWidget {
  const _ImagePickerWidget();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: Colors.white, fontSize: 16.sp);
    Widget camera = Text('settings-upload-avatar-camera'.tr, style: style);
    Widget gallery = Text('settings-upload-avatar-album'.tr, style: style);

    camera = InkButton(
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.symmetric(vertical: 14.h),
      borderRadius: BorderRadius.zero,
      onPressed: () {
        Nav.back(false);
      },
      child: Center(child: camera),
    );
    gallery = InkButton(
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.symmetric(vertical: 14.h),
      borderRadius: BorderRadius.zero,
      onPressed: () {
        Nav.back(true);
      },
      child: Center(child: gallery),
    );

    return Material(
      color: const Color(0xFF191632),
      clipBehavior: Clip.hardEdge,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            camera,
            Divider(color: Colors.grey.shade900, height: 1.h, thickness: 1.h),
            gallery,
          ],
        ),
      ),
    );
  }
}
