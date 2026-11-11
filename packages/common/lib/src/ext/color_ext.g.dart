// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'color_ext.dart';

// **************************************************************************
// Generator: AppColorsGeneratorForAnnotation
// **************************************************************************

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

extension AppColorsS on State<StatefulWidget> {
  AppColors get colors => Theme.of(context).extension<AppColors>()!;
}

final class AppColors extends ThemeExtension<AppColors> {
  final Color textFieldBorderColor;
  final Color textFieldBorderColorFocus;
  final Color editTextColor;
  final Color editTextHintColor;
  final Color inkOverlayColor;
  final Color inkBackgroundColor;
  final Color inkTextColor;
  final Color inkCancelOverlayColor;
  const new({
    required this.textFieldBorderColor,
    required this.textFieldBorderColorFocus,
    required this.editTextColor,
    required this.editTextHintColor,
    required this.inkOverlayColor,
    required this.inkBackgroundColor,
    required this.inkTextColor,
    required this.inkCancelOverlayColor,
  });

  @override
  AppColors copyWith({
    Color? textFieldBorderColor,
    Color? textFieldBorderColorFocus,
    Color? editTextColor,
    Color? editTextHintColor,
    Color? inkOverlayColor,
    Color? inkBackgroundColor,
    Color? inkTextColor,
    Color? inkCancelOverlayColor,
  }) {
    return .new(
      textFieldBorderColor: textFieldBorderColor ?? this.textFieldBorderColor,
      textFieldBorderColorFocus:
          textFieldBorderColorFocus ?? this.textFieldBorderColorFocus,
      editTextColor: editTextColor ?? this.editTextColor,
      editTextHintColor: editTextHintColor ?? this.editTextHintColor,
      inkOverlayColor: inkOverlayColor ?? this.inkOverlayColor,
      inkBackgroundColor: inkBackgroundColor ?? this.inkBackgroundColor,
      inkTextColor: inkTextColor ?? this.inkTextColor,
      inkCancelOverlayColor:
          inkCancelOverlayColor ?? this.inkCancelOverlayColor,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    return .new(
      textFieldBorderColor: .lerp(
        textFieldBorderColor,
        other?.textFieldBorderColor,
        t,
      )!,
      textFieldBorderColorFocus: .lerp(
        textFieldBorderColorFocus,
        other?.textFieldBorderColorFocus,
        t,
      )!,
      editTextColor: .lerp(editTextColor, other?.editTextColor, t)!,
      editTextHintColor: .lerp(editTextHintColor, other?.editTextHintColor, t)!,
      inkOverlayColor: .lerp(inkOverlayColor, other?.inkOverlayColor, t)!,
      inkBackgroundColor: .lerp(
        inkBackgroundColor,
        other?.inkBackgroundColor,
        t,
      )!,
      inkTextColor: .lerp(inkTextColor, other?.inkTextColor, t)!,
      inkCancelOverlayColor: .lerp(
        inkCancelOverlayColor,
        other?.inkCancelOverlayColor,
        t,
      )!,
    );
  }
}

enum AppColorsType {
  light(
    .new(
      textFieldBorderColor: .from(
        alpha: 0.28627450980392155,
        red: 0.4196078431372549,
        green: 0.4196078431372549,
        blue: 0.4196078431372549,
        colorSpace: .sRGB,
      ),
      textFieldBorderColorFocus: .from(
        alpha: 1.0,
        red: 0.11372549019607843,
        green: 0.4745098039215686,
        blue: 0.8862745098039215,
        colorSpace: .sRGB,
      ),
      editTextColor: .from(
        alpha: 1.0,
        red: 0.2,
        green: 0.2,
        blue: 0.2,
        colorSpace: .sRGB,
      ),
      editTextHintColor: .from(
        alpha: 1.0,
        red: 0.6274509803921569,
        green: 0.6274509803921569,
        blue: 0.6274509803921569,
        colorSpace: .sRGB,
      ),
      inkOverlayColor: .from(
        alpha: 0.20784313725490197,
        red: 1.0,
        green: 1.0,
        blue: 1.0,
        colorSpace: .sRGB,
      ),
      inkBackgroundColor: .from(
        alpha: 1.0,
        red: 0.12941176470588237,
        green: 0.5882352941176471,
        blue: 0.9529411764705882,
        colorSpace: .sRGB,
      ),
      inkTextColor: .from(
        alpha: 1.0,
        red: 1.0,
        green: 1.0,
        blue: 1.0,
        colorSpace: .sRGB,
      ),
      inkCancelOverlayColor: .from(
        alpha: 0.20784313725490197,
        red: 0.6274509803921569,
        green: 0.6274509803921569,
        blue: 0.6274509803921569,
        colorSpace: .sRGB,
      ),
    ),
  ),
  dark(
    .new(
      textFieldBorderColor: .from(
        alpha: 1.0,
        red: 0.8666666666666667,
        green: 0.8666666666666667,
        blue: 0.8666666666666667,
        colorSpace: .sRGB,
      ),
      textFieldBorderColorFocus: .from(
        alpha: 1.0,
        red: 0.11372549019607843,
        green: 0.4745098039215686,
        blue: 0.8862745098039215,
        colorSpace: .sRGB,
      ),
      editTextColor: .from(
        alpha: 1.0,
        red: 0.8666666666666667,
        green: 0.8666666666666667,
        blue: 0.8666666666666667,
        colorSpace: .sRGB,
      ),
      editTextHintColor: .from(
        alpha: 0.39215686274509803,
        red: 0.39215686274509803,
        green: 0.39215686274509803,
        blue: 0.39215686274509803,
        colorSpace: .sRGB,
      ),
      inkOverlayColor: .from(
        alpha: 0.20784313725490197,
        red: 1.0,
        green: 1.0,
        blue: 1.0,
        colorSpace: .sRGB,
      ),
      inkBackgroundColor: .from(
        alpha: 1.0,
        red: 0.12941176470588237,
        green: 0.5882352941176471,
        blue: 0.9529411764705882,
        colorSpace: .sRGB,
      ),
      inkTextColor: .from(
        alpha: 1.0,
        red: 0.2,
        green: 0.2,
        blue: 0.2,
        colorSpace: .sRGB,
      ),
      inkCancelOverlayColor: .from(
        alpha: 0.20784313725490197,
        red: 0.6274509803921569,
        green: 0.6274509803921569,
        blue: 0.6274509803921569,
        colorSpace: .sRGB,
      ),
    ),
  );

  final AppColors colors;
  const new(this.colors);
}

final class _ColorGroup {
  const new({required this.light, required this.dark});
  final Color light;
  final Color dark;
}

const appColorsMap = <String, _ColorGroup>{
  "textFieldBorderColor": .new(
    light: .from(
      alpha: 0.28627450980392155,
      red: 0.4196078431372549,
      green: 0.4196078431372549,
      blue: 0.4196078431372549,
      colorSpace: .sRGB,
    ),
    dark: .from(
      alpha: 1.0,
      red: 0.8666666666666667,
      green: 0.8666666666666667,
      blue: 0.8666666666666667,
      colorSpace: .sRGB,
    ),
  ),
  "textFieldBorderColorFocus": .new(
    light: .from(
      alpha: 1.0,
      red: 0.11372549019607843,
      green: 0.4745098039215686,
      blue: 0.8862745098039215,
      colorSpace: .sRGB,
    ),
    dark: .from(
      alpha: 1.0,
      red: 0.11372549019607843,
      green: 0.4745098039215686,
      blue: 0.8862745098039215,
      colorSpace: .sRGB,
    ),
  ),
  "editTextColor": .new(
    light: .from(
      alpha: 1.0,
      red: 0.2,
      green: 0.2,
      blue: 0.2,
      colorSpace: .sRGB,
    ),
    dark: .from(
      alpha: 1.0,
      red: 0.8666666666666667,
      green: 0.8666666666666667,
      blue: 0.8666666666666667,
      colorSpace: .sRGB,
    ),
  ),
  "editTextHintColor": .new(
    light: .from(
      alpha: 1.0,
      red: 0.6274509803921569,
      green: 0.6274509803921569,
      blue: 0.6274509803921569,
      colorSpace: .sRGB,
    ),
    dark: .from(
      alpha: 0.39215686274509803,
      red: 0.39215686274509803,
      green: 0.39215686274509803,
      blue: 0.39215686274509803,
      colorSpace: .sRGB,
    ),
  ),
  "inkOverlayColor": .new(
    light: .from(
      alpha: 0.20784313725490197,
      red: 1.0,
      green: 1.0,
      blue: 1.0,
      colorSpace: .sRGB,
    ),
    dark: .from(
      alpha: 0.20784313725490197,
      red: 1.0,
      green: 1.0,
      blue: 1.0,
      colorSpace: .sRGB,
    ),
  ),
  "inkBackgroundColor": .new(
    light: .from(
      alpha: 1.0,
      red: 0.12941176470588237,
      green: 0.5882352941176471,
      blue: 0.9529411764705882,
      colorSpace: .sRGB,
    ),
    dark: .from(
      alpha: 1.0,
      red: 0.12941176470588237,
      green: 0.5882352941176471,
      blue: 0.9529411764705882,
      colorSpace: .sRGB,
    ),
  ),
  "inkTextColor": .new(
    light: .from(
      alpha: 1.0,
      red: 1.0,
      green: 1.0,
      blue: 1.0,
      colorSpace: .sRGB,
    ),
    dark: .from(alpha: 1.0, red: 0.2, green: 0.2, blue: 0.2, colorSpace: .sRGB),
  ),
  "inkCancelOverlayColor": .new(
    light: .from(
      alpha: 0.20784313725490197,
      red: 0.6274509803921569,
      green: 0.6274509803921569,
      blue: 0.6274509803921569,
      colorSpace: .sRGB,
    ),
    dark: .from(
      alpha: 0.20784313725490197,
      red: 0.6274509803921569,
      green: 0.6274509803921569,
      blue: 0.6274509803921569,
      colorSpace: .sRGB,
    ),
  ),
};
