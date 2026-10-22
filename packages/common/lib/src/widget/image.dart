import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

import '../utils/date_format.dart';
import 'image_picker.dart';

enum ImageSuf {
  png('.png'),
  webp('.webp'),
  jpg('.jpg');

  final String suf;
  const ImageSuf(this.suf);
}

/// 从`packages/assets`资源库获取图片资源
Image getImage(
  String basename, {
  double? height,
  double? width,
  BoxFit? fit,
  Color? color,
  Key? key,
  Alignment? alignment,
  Widget? placeholder,
  ImageFrameBuilder? builder,
  ImageSuf suf = ImageSuf.png,
}) {
  return Image.asset(
    'assets/images/$basename${suf.suf}',
    key: key,
    height: height,
    width: width,
    color: color,
    fit: fit,
    alignment: alignment ?? Alignment.center,
    frameBuilder: builder,
    errorBuilder: (context, error, stackTrace) {
      assert(false, '确保 assets/images/ 中存在 $basename${suf.suf}');
      if (suf == ImageSuf.png) {
        return getImage(
          basename,
          height: height,
          width: width,
          fit: fit,
          key: key,
          color: color,
          alignment: alignment,
          placeholder: placeholder,
          suf: ImageSuf.webp,
        );
      }
      return placeholder ?? SizedBox(height: height, width: width);
    },
    package: 'assets',
  );
}

Widget getLottie(
  String basename, {
  double? height,
  double? width,
  BoxFit? fit,
  Key? key,
  Widget? placeholder,
  String suf = '.json',
}) {
  return Lottie.asset(
    'assets/lottie/$basename$suf',
    animate: true,
    repeat: true,
    key: key,
    width: width,
    height: height,
    package: 'assets',
    fit: fit,
    errorBuilder: (context, error, stackTrace) {
      return placeholder ?? SizedBox(height: height, width: width);
    },
  );
}

Widget getLocalImage(
  String path, {
  double? height,
  double? width,
  BoxFit? fit,
}) {
  return Image(
    image: FileImage(File(path)),
    height: height,
    width: width,
    fit: fit,
  );
}

ImageProvider getImageProvider(
  String basename, {
  double? height,
  double? width,
  BoxFit? fit,
  Color? color,
  String suf = '.png',
}) {
  return Image.asset(
    'assets/images/$basename$suf',
    height: height,
    width: width,
    color: color,
    fit: fit,
    package: 'assets',
  ).image;
}

Widget loadImage(
  String name, {
  double? height,
  double? width,
  BoxFit? fit,
  bool isCircle = false,
  Widget? placeholder,
  Color? color,
}) {
  color ??= const Color.fromARGB(33, 201, 201, 201);
  late final child =
      placeholder ??
      Container(
        height: height,
        width: width,
        decoration: isCircle
            ? ShapeDecoration(shape: const StadiumBorder(), color: color)
            : null,
        color: isCircle ? null : color,
      );

  if (name.isEmpty) return child;

  final image = CachedNetworkImage(
    imageUrl: name,
    height: height,
    width: width,
    fit: fit,
    fadeInDuration: const Duration(milliseconds: 300),
    fadeOutDuration: const Duration(milliseconds: 500),
    errorWidget: (context, url, error) {
      return child;
    },
    placeholder: (context, url) {
      return child;
    },
  );

  return image;
}

/// 获取图片宽高，加载错误情况返回 Rect.zero.（单位 px）
Future<Rect> getImageWH({
  Image? image,
  String? url,
  String? localUrl,
  String? package,
}) {
  if (image == null &&
      url?.isNotEmpty != true &&
      localUrl?.isNotEmpty != true) {
    return Future.value(Rect.zero);
  }
  Completer<Rect> completer = Completer<Rect>.sync();
  // Image img = image ??
  //     ((url != null && url.isNotEmpty)
  //         ? Image.network(url)
  //         : Image.asset(localUrl!, package: package));
  ImageProvider img;
  if (url != null) {
    img = CachedNetworkImageProvider(url);
  } else if (image != null) {
    img = image.image;
  } else {
    img = AssetImage(localUrl!, package: package);
  }
  late ImageStreamListener listener;

  Rect? rect;
  final stream = img.resolve(const ImageConfiguration());
  stream.addListener(
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        completer.complete(
          rect = Rect.fromLTWH(
            0,
            0,
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          ),
        );
        SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
          stream.removeListener(listener);
          info.dispose();
        });
      },
      onError: (Object exception, StackTrace? stackTrace) {
        completer.completeError(exception, stackTrace);
        stream.removeListener(listener);
      },
    ),
  );

  // 同步
  if (rect != null) {
    return SynchronousFuture(rect!);
  }
  return completer.future;
}

/// 获取图片宽高，加载错误情况返回 Rect.zero.（单位 px）
Future<ImageInfo?> getRawImage({
  String? url,
  String? localUrl,
  String? package,
  Uint8List? data,
  Size? size,
}) {
  if (url?.isNotEmpty != true && localUrl?.isNotEmpty != true && data == null) {
    return SynchronousFuture(null);
  }

  final completer = Completer<ImageInfo>.sync();

  ImageProvider img;
  if (url != null && url.isNotEmpty) {
    img = CachedNetworkImageProvider(url);
  } else if (data != null) {
    img = MemoryImage(data);
  } else {
    img = AssetImage(localUrl!, package: package);
  }
  late ImageStreamListener listener;
  if (size case var size?) {
    img = ResizeImage(
      img,
      width: size.width.toInt(),
      height: size.height.toInt(),
      allowUpscaling: true,
    );
  }

  ImageInfo? infoSync;
  final stream = img.resolve(const ImageConfiguration());
  stream.addListener(
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        completer.complete(infoSync = info);
        SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
          stream.removeListener(listener);
        });
      },
      onError: (Object exception, StackTrace? stackTrace) {
        completer.completeError(exception, stackTrace);
        stream.removeListener(listener);
      },
    ),
  );

  // 同步
  if (infoSync case var infoSync?) {
    return SynchronousFuture(infoSync);
  }

  return completer.future;
}

/// [position] 所有值都在[0,1]范围内
Future<bool> saveImage(
  String url,
  String qrData, {
  String? localPath,
  Rect position = Rect.zero,
}) async {
  final record = ui.PictureRecorder();
  final canvas = ui.Canvas(record);

  final provider = await getRawImage(localUrl: localPath, url: url);

  var width = 0;
  var height = 0;

  if (provider?.image case var image?) {
    width = image.width;
    height = image.height;
    canvas.drawImage(image, Offset.zero, Paint());

    final qrWidth = width * position.width.clamp(0.0, 1.0);
    final qrHeight = height * position.height.clamp(0.0, 1.0);

    final qrImage = await getRawImage(
      data: base64Decode(qrData),
      size: Size(qrWidth, qrHeight),
    );

    if (qrImage?.image case var image?) {
      final offset = Offset(
        width * position.left.clamp(0.0, 1.0),
        height * position.top.clamp(0.0, 1.0),
      );

      canvas.drawImage(image, offset, Paint());
      qrImage?.dispose();
    }
  } else {
    return false;
  }

  final picture = record.endRecording();

  final img = await picture.toImage(width, height);
  final imgBuffer = await img.toByteData(format: ui.ImageByteFormat.png);

  if (imgBuffer case var imgBuffer?) {
    await ImagePickerUtils.savePicture(
      imgBuffer.buffer.asUint8List(),
      'save-${formatDateYMdHms(DateTime.now())}',
    );
    // okToast('success');
    img.dispose();
    picture.dispose();
    return true;
  }

  img.dispose();
  picture.dispose();
  return false;
}
