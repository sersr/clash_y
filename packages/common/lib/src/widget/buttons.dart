import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// ios 按钮样式
class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.onTap,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
    this.color,
    this.disableColor = CupertinoColors.quaternarySystemFill,
    this.borderRadius = const BorderRadius.all(Radius.circular(8.0)),
    required this.child,
  });
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius? borderRadius;
  final bool enabled;
  final Color? color;
  final Color disableColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    Widget current = child;

    if (padding != null) {
      current = Padding(padding: padding!, child: current);
    }

    return CupertinoButton(
      onPressed: !enabled ? null : onTap,
      padding: EdgeInsets.zero,
      borderRadius: borderRadius,
      color: color,
      disabledColor: disableColor,
      minimumSize: null,
      child: current,
    );
  }
}

VoidCallback? _wrapTap(VoidCallback? onTap) {
  if (onTap == null) return null;
  return () {
    HapticFeedback.heavyImpact();
    onTap();
  };
}

/// android 样式
class InkButton extends ButtonStyleButton {
  const InkButton({
    super.key,
    this.backgroundColor,
    this.forgegroundColor,
    super.autofocus = false,
    super.clipBehavior = Clip.antiAlias,
    super.focusNode,
    super.onFocusChange,
    super.onHover,
    super.onLongPress,
    super.style,
    super.statesController,
    super.onPressed,
    this.side,
    this.padding = const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.isStadium = false,
    this.overlayColor,
    this.duration,
    this.elevation,
    this.feedback = false,
    this.shape,
    this.splashFactory,
    required super.child,
  });

  const InkButton.text({
    super.key,
    this.backgroundColor = const Color(0x00FFFFFF),
    this.forgegroundColor,
    super.autofocus = false,
    super.clipBehavior = Clip.antiAlias,
    super.focusNode,
    super.onFocusChange,
    super.onHover,
    super.onLongPress,
    super.style,
    super.statesController,
    super.onPressed,
    this.side,
    this.padding = const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.isStadium = false,
    this.overlayColor = const Color(0x1FFFFFFF),
    this.duration,
    this.elevation,
    this.feedback = false,
    this.shape,
    this.splashFactory,
    required super.child,
  });

  const InkButton.outlined({
    super.key,
    this.backgroundColor,
    this.forgegroundColor,
    super.autofocus = false,
    super.clipBehavior = Clip.antiAlias,
    super.focusNode,
    super.onFocusChange,
    super.onHover,
    super.onLongPress,
    super.style,
    super.statesController,
    super.onPressed,
    this.side = const BorderSide(color: Colors.grey),
    this.padding = const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.isStadium = false,
    this.overlayColor,
    this.duration,
    this.elevation,
    this.feedback = false,
    this.shape,
    this.splashFactory,
    required super.child,
  });

  final Color? backgroundColor;
  final Color? forgegroundColor;
  final BorderSide? side;
  final BorderRadius borderRadius;
  final EdgeInsets? padding;
  final Duration? duration;
  final double? elevation;

  final Color? overlayColor;
  final bool feedback;

  /// 最大圆角矩形
  final bool isStadium;
  final OutlinedBorder? shape;

  final InteractiveInkFeatureFactory? splashFactory;
  @override
  VoidCallback? get onPressed {
    if (!feedback) return super.onPressed;
    return _wrapTap(super.onPressed);
  }

  @override
  ButtonStyle defaultStyleOf(BuildContext context) {
    return ButtonStyle(
      visualDensity: VisualDensity.standard,
      maximumSize: const WidgetStatePropertyAll(Size.infinite),
      padding: WidgetStatePropertyAll(padding),
      minimumSize: WidgetStateProperty.all(Size.zero),
      animationDuration: duration ?? const Duration(milliseconds: 200),
      elevation: WidgetStatePropertyAll(elevation ?? 0),
      alignment: Alignment.center,
      overlayColor: WidgetStatePropertyAll(
        overlayColor ?? Colors.grey.shade400,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      mouseCursor: const WidgetStatePropertyAll(MouseCursor.defer),
      side: WidgetStatePropertyAll(side),
      backgroundColor: WidgetStatePropertyAll(
        backgroundColor ?? Colors.grey.shade200,
      ),
      foregroundColor: WidgetStatePropertyAll(forgegroundColor),
      splashFactory: splashFactory ?? InkRipple.splashFactory,
      shadowColor: const WidgetStatePropertyAll(null),
      shape: WidgetStatePropertyAll(
        shape ??
            (isStadium
                ? StadiumBorder(side: side ?? BorderSide.none)
                : RoundedRectangleBorder(
                    side: side ?? BorderSide.none,
                    borderRadius: borderRadius,
                  )),
      ),
    );
  }

  @override
  ButtonStyle? themeStyleOf(BuildContext context) {
    final inkStyle = Theme.of(context).extensions[InkStyle];
    if (inkStyle is InkStyle) {
      return inkStyle.style;
    }
    return null;
  }
}

class MaterialStateOpacity implements WidgetStateProperty<Color?> {
  const MaterialStateOpacity(this.color);
  final Color? color;

  @override
  Color? resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) {
      return color?.withValues(alpha: 0.5);
    }
    return color;
  }
}

class InkStyle extends ThemeExtension<InkStyle> {
  final ButtonStyle style;

  InkStyle({required this.style});
  @override
  ThemeExtension<InkStyle> copyWith() {
    return InkStyle(style: style.copyWith());
  }

  @override
  ThemeExtension<InkStyle> lerp(ThemeExtension<InkStyle>? other, double t) {
    if (other is! InkStyle) {
      return other ?? this;
    }
    return InkStyle(style: ButtonStyle.lerp(style, other.style, t) ?? style);
  }
}
