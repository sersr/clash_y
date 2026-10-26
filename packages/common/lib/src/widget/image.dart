import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 从`packages/assets`资源库获取图片资源，支持重复平铺
class RepeatImage extends StatelessWidget {
  const RepeatImage(
    this.name, {
    super.key,
    this.height,
    this.width,
    this.fit,
    this.color,
    this.alignment,
    this.placeholder,
    this.builder,
    this.repeat = ImageRepeat.noRepeat,
  });

  final String name;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final Color? color;
  final Alignment? alignment;
  final Widget? placeholder;
  final ImageFrameBuilder? builder;
  final ImageRepeat repeat;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(name, package: 'common'),
          fit: fit ?? BoxFit.cover,
          alignment: alignment ?? Alignment.center,
          repeat: repeat,
          colorFilter: color != null
              ? ColorFilter.mode(color!, BlendMode.srcIn)
              : null,
        ),
      ),
    );
  }
}

class SvgImage extends StatelessWidget {
  const SvgImage(
    this.name, {
    super.key,
    this.height,
    this.width,
    this.fit,
    this.color,
    this.alignment,
    this.placeholder,
    this.builder,
  });

  final String name;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final ColorFilter? color;
  final Alignment? alignment;
  final Widget? placeholder;
  final ImageFrameBuilder? builder;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      name,
      key: key,
      height: height,
      width: width,
      colorFilter: color,
      fit: fit ?? BoxFit.contain,
      alignment: alignment ?? Alignment.center,
      errorBuilder: (context, error, stackTrace) {
        return placeholder ?? SizedBox(height: height, width: width);
      },
      package: 'common',
    );
  }
}

class SvgNetImage extends StatelessWidget {
  const SvgNetImage(
    this.name, {
    super.key,
    this.height,
    this.width,
    this.fit,
    this.color,
    this.alignment,
    this.placeholder,
    this.builder,
  });

  final String name;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final ColorFilter? color;
  final Alignment? alignment;
  final Widget? placeholder;
  final ImageFrameBuilder? builder;

  @override
  Widget build(BuildContext context) {
    // return CachedNetworkSVGImage(
    //   name,
    //   height: height,
    //   width: width,
    //   fit: fit ?? BoxFit.contain,
    //   alignment: alignment ?? Alignment.center,
    //   placeholder: placeholder,
    //   colorFilter: color,
    //   errorWidget: placeholder ?? SizedBox(height: height, width: width),
    // );
    return SvgPicture.network(
      name,
      key: key,
      height: height,
      width: width,
      colorFilter: color,
      fit: fit ?? BoxFit.contain,
      alignment: alignment ?? Alignment.center,
      errorBuilder: (context, error, stackTrace) {
        return placeholder ?? SizedBox(height: height, width: width);
      },
    );
  }
}

class SvgFileImage extends StatelessWidget {
  const SvgFileImage(
    this.file, {
    super.key,
    this.height,
    this.width,
    this.fit,
    this.color,
    this.alignment,
    this.placeholder,
    this.builder,
  });

  final String file;

  final double? height;
  final double? width;
  final BoxFit? fit;
  final ColorFilter? color;
  final Alignment? alignment;
  final Widget? placeholder;
  final ImageFrameBuilder? builder;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.file(
      File(file),
      key: key,
      height: height,
      width: width,
      colorFilter: color,
      fit: fit ?? BoxFit.contain,
      alignment: alignment ?? Alignment.center,
      errorBuilder: (context, error, stackTrace) {
        return placeholder ?? SizedBox(height: height, width: width);
      },
    );
  }
}

class SvgStrImage extends StatelessWidget {
  const SvgStrImage(
    this.svgStr, {
    super.key,
    this.height,
    this.width,
    this.fit,
    this.color,
    this.alignment,
    this.placeholder,
    this.builder,
  });

  final String svgStr;

  final double? height;
  final double? width;
  final BoxFit? fit;
  final ColorFilter? color;
  final Alignment? alignment;
  final Widget? placeholder;
  final ImageFrameBuilder? builder;

  @override
  Widget build(BuildContext context) {
    if (svgStr.isEmpty) {
      return placeholder ?? SizedBox(height: height, width: width);
    }

    return SvgPicture.string(
      svgStr,
      key: key,
      height: height,
      width: width,
      colorFilter: color,
      fit: fit ?? BoxFit.contain,
      alignment: alignment ?? Alignment.center,
      errorBuilder: (context, error, stackTrace) {
        return placeholder ?? SizedBox(height: height, width: width);
      },
    );
  }
}

/// 获取图片宽高，加载错误情况返回 Rect.zero.（单位 px）
Future<Rect> getImageSize({
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

/// 从`packages/assets`资源库获取图片资源
class AImage extends StatelessWidget {
  const AImage(
    this.name, {
    super.key,
    this.height,
    this.width,
    this.fit,
    this.color,
    this.alignment,
    this.placeholder,
    this.builder,
    this.package = 'common',
  });

  final String name;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final Color? color;
  final Alignment? alignment;
  final Widget? placeholder;
  final ImageFrameBuilder? builder;
  final String? package;

  @override
  Widget build(BuildContext context) {
    if (name.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        name,
        key: key,
        height: height,
        width: width,
        colorFilter: color != null
            ? ColorFilter.mode(color!, BlendMode.srcIn)
            : null,
        fit: fit ?? BoxFit.contain,
        alignment: alignment ?? Alignment.center,
        package: package,
        errorBuilder: (context, error, stackTrace) {
          return placeholder ?? SizedBox(height: height, width: width);
        },
      );
    }

    return Image.asset(
      name,
      key: key,
      height: height,
      width: width,
      color: color,
      fit: fit,
      alignment: alignment ?? Alignment.center,
      frameBuilder: builder,
      errorBuilder: (context, error, stackTrace) {
        return placeholder ?? SizedBox(height: height, width: width);
      },
      package: package,
    );
  }
}

class NetImage extends StatelessWidget {
  const NetImage(
    this.name, {
    super.key,
    this.height,
    this.width,
    this.fit,
    this.circle = false,
    this.placeholder,
    this.color = const Color.fromARGB(33, 201, 201, 201),
    this.imageBuilder,
    this.errorWidget,
    this.progressIndicatorBuilder,
    this.cacheKey,
  });

  final String name;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final bool circle;
  final Widget? placeholder;
  final Color color;
  final Widget Function(BuildContext context, Widget child)? imageBuilder;
  final Widget? errorWidget;
  final ProgressIndicatorBuilder? progressIndicatorBuilder;
  final String? cacheKey;

  @override
  Widget build(BuildContext context) {
    late final child =
        placeholder ??
        Container(
          height: height,
          width: width,
          decoration: circle
              ? ShapeDecoration(shape: const StadiumBorder(), color: color)
              : null,
          color: circle ? null : color,
        );

    if (name.isEmpty) return child;

    // Decode at display size × DPR so list icons/avatars don't keep full-res bitmaps.
    // Skip when size is unknown — caller may show full-bleed images.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memW = width != null && width!.isFinite && width! > 0
        ? max(1, (width! * dpr).round())
        : null;
    final memH = height != null && height!.isFinite && height! > 0
        ? max(1, (height! * dpr).round())
        : null;

    final image = CachedNetworkImage(
      key: key,
      imageUrl: name,
      height: height,
      width: width,
      fit: fit,
      cacheKey: cacheKey,
      memCacheWidth: memW,
      memCacheHeight: memH,
      fadeInDuration: const Duration(milliseconds: 300),
      fadeOutDuration: const Duration(milliseconds: 500),
      errorWidget: (context, url, error) {
        return errorWidget ?? child;
      },
      progressIndicatorBuilder: progressIndicatorBuilder,
      imageBuilder: imageBuilder != null
          ? (context, imageProvider) => imageBuilder!(
              context,
              Image(
                image: imageProvider,
                fit: fit,
                width: width,
                height: height,
              ),
            )
          : null,
      placeholder: progressIndicatorBuilder != null
          ? null
          : (context, url) {
              return child;
            },
    );

    return image;
  }
}
