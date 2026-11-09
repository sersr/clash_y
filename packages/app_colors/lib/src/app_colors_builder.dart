import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:app_colors/app_colors.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

bool isSameType<T>(String? name) {
  return T.toString() == name;
}

class AppColorsGeneratorForAnnotation
    extends GeneratorForAnnotation<AppColorsReg> {
  @override
  dynamic generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    for (final meta in element.metadata.annotations) {
      final value = meta.computeConstantValue();
      if (value == null) continue;
      final name = value.type?.element?.name;

      if ('AppColorsReg' == name) {
        final colors = value.getField('colors')?.toMapValue();
        final className =
            value.getField('className')?.toStringValue() ?? 'AppColors';

        if (colors == null) continue;
        final map = <String, Map<String, String>>{};
        for (var item in colors.entries) {
          final name = item.key!.toStringValue()!;

          if (item.value?.toRecordValue() case var record?) {
            for (var item in record.named.entries) {
              final m = map[name] ??= {};

              m[item.key] = genColor(item.value);
            }
            continue;
          }

          if (item.value case var color?) {
            final m = map[name] ??= {};
            m['light'] = genColor(color);
            continue;
          }
        }

        return gen(className, map);
      }
    }
  }

  DartObject? getFieldInSuperclasses(DartObject object, String name) {
    var current = object;

    while (true) {
      final field = current.getField(name);
      if (field != null) return field;

      final parent = current.getField('(super)');
      if (parent == null) return null;
      current = parent;
    }
  }

  String genColor(DartObject color) {
    final a = getFieldInSuperclasses(color, 'a')?.toDoubleValue();
    final r = getFieldInSuperclasses(color, 'r')?.toDoubleValue();
    final g = getFieldInSuperclasses(color, 'g')?.toDoubleValue();
    final b = getFieldInSuperclasses(color, 'b')?.toDoubleValue();
    final colorSpace = getFieldInSuperclasses(
      color,
      'colorSpace',
    )?.getField('_name')?.toStringValue();

    return 'Color.from(alpha: $a, red: $r, green: $g, blue: $b, colorSpace: .$colorSpace)';
  }

  String gen(String className, Map<String, Map<String, String>> colors) {
    final buffer = StringBuffer();

    buffer.write('''

extension ${className}X on BuildContext {
  $className get colors => Theme.of(this).extension<$className>()!;
}

extension ${className}S on State<StatefulWidget> {
  $className get colors => Theme.of(context).extension<$className>()!;
}

final class $className extends ThemeExtension<$className> {

''');

    buffer.writeAll(colors.keys.map((e) => 'final Color $e;\n'));

    buffer.write('''
const new({
${colors.keys.map((e) => "required this.$e,\n").join()}
});

@override
$className copyWith({

${colors.keys.map((e) => "Color? $e,\n").join()}

}) {

return .new(
${colors.keys.map((e) => "$e: $e ?? this.$e,\n").join()}
);

}

@override
$className lerp(covariant $className? other, double t) {
  if (other is! $className) return this;

  return .new(
  ${colors.keys.map((e) => "$e: Color.lerp($e, other.$e, t,)!,\n").join()}
  );

}

''');
    buffer.write('\n}\n');

    final type = colors.values.firstOrNull;
    if (type != null) {
      buffer.write('''
enum ${className}Type {
${type.keys.map((e) => '$e(.new('
          '${colors.map((k, v) => .new(k, '$k: ${v[e]}')).values.join(',\n')}'
          '))').join(',')}

;

final $className colors;
const new(this.colors);
}



''');
    }

    return buffer.toString();
  }
}

String getToCamel(String name) {
  return name.replaceAllMapped(RegExp('[_-]([A-Za-z]+)'), (match) {
    final data = match[1]!;
    final first = data.substring(0, 1).toUpperCase();
    final second = data.substring(1);
    return '$first$second';
  });
}

String getDartMemberName(String name) {
  final camel = getToCamel(name);
  if (camel.length <= 1) return camel.toLowerCase();
  final first = camel.substring(0, 1).toLowerCase();
  final others = camel.substring(1);
  return '$first$others';
}

Builder appColorsBuilder(BuilderOptions options) =>
    SharedPartBuilder([AppColorsGeneratorForAnnotation()], 'app_colors');
