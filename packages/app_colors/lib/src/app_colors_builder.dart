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
            if (color.type?.element case ClassElement e) {
              final names = e.allSupertypes.map((e) => e.element.name);
              if (e.name == 'Color' || names.contains('Color')) {
                final m = map[name] ??= {};
                m['light'] = genColor(color);
                continue;
              }

              final fileds = getAllFileds(e)
                  .where((e) => e.name != 'hashCode')
                  .map((e) => (e.name, color.getFieldE(e.name ?? '')))
                  .toList();
              for (var item in fileds) {
                final key = item.$1 ?? '';
                final color = item.$2;
                if (color?.type?.element case ClassElement e) {
                  final names = e.allSupertypes.map((e) => e.element.name);

                  if (e.name == 'Color' || names.contains('Color')) {
                    final m = map[name] ??= {};
                    m[key] = genColor(color!);
                  }
                }
              }
            }
          }
        }

        return gen(className, map);
      }
    }
  }

  List<FieldElement> getAllFileds(Element e) {
    if (e case ClassElement e when e.name != 'Object') {
      final List<FieldElement> list = .from(e.fields);
      for (var item in e.allSupertypes) {
        list.addAll(getAllFileds(item.element));
      }
      return list;
    }

    return const [];
  }

  String genColor(DartObject color) {
    final a = color.getFieldE('a')?.toDoubleValue();
    final r = color.getFieldE('r')?.toDoubleValue();
    final g = color.getFieldE('g')?.toDoubleValue();
    final b = color.getFieldE('b')?.toDoubleValue();
    final colorSpace = color
        .getFieldE('colorSpace')
        ?.getField('_name')
        ?.toStringValue();

    return '.from(alpha: $a, red: $r, green: $g, blue: $b, colorSpace: .$colorSpace)';
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
const new(
${colors.keys.isEmpty ? '': "{"}

${colors.keys.map((e) => "required this.$e,\n").join()}

${colors.keys.isEmpty ? '': "}"}
);

@override
$className copyWith( 
${colors.keys.isEmpty ? '': "{"}

${colors.keys.map((e) => "Color? $e,\n").join()}

${colors.keys.isEmpty ? '': "}"}
) {

return .new(
${colors.keys.map((e) => "$e: $e ?? this.$e,\n").join()}
);

}

@override
$className lerp(covariant $className? other, double t) {
  return .new(
  ${colors.keys.map((e) => "$e: .lerp($e, other?.$e, t,)!,\n").join()}
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

extension on DartObject {
  DartObject? getFieldE(String name) {
    var current = this;

    while (true) {
      final field = current.getField(name);
      if (field != null) return field;

      final parent = current.getField('(super)');
      if (parent == null) return null;
      current = parent;
    }
  }
}
