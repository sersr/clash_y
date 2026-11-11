import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

dynamic genRoot(
  String className,
  List<(String?, DartObject?)> fields,
  bool isMap,
  bool genAnother,
) {
  final map = <String, Map<String, String>>{};
  final ano = <String, String>{};

  for (var item in fields) {
    final name = item.$1 ?? '';
    ano[name] = genClassCall(item.$2!, isMap);

    if (item.$2?.toRecordValue() case var record?) {
      for (var item in record.named.entries) {
        final m = map[name] ??= {};

        m[item.key] = genColor(item.value);
      }
      continue;
    }

    if (item.$2 case var color?) {
      if (color.type?.element case ClassElement e) {
        final names = e.allSupertypes.map((e) => e.element.name);
        if (e.name == 'Color' || names.contains('Color')) {
          final m = map[name] ??= {};
          m['light'] = genColor(color);
          continue;
        }

        final fields = getAllFields(e)
            .where((e) => e.name != 'hashCode')
            .map((e) => (e.name, color.getFieldE(e.name ?? '')))
            .toList();
        for (var item in fields) {
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

  final text = gen(className, map);
  if (!genAnother) {
    return text;
  }

  final buf = StringBuffer(text);

  buf.writeln(genClassType(fields.firstOrNull!.$2!));

  if (isMap) {
    buf.write('''
final class ${className}Fields {
const new();


''');

    for (var key in ano.keys) {
      buf.writeln('final $key = ${ano[key]};');
    }

    buf.writeln('}');
  } else {
    final typeName = fields.firstOrNull?.$2?.type?.element?.name;
    buf.write('''
const ${getDartMemberName(className)}Map = <String,$typeName> {
''');

    for (var key in ano.keys) {
      buf.writeln('"$key": ${ano[key]},');
    }
    buf.write('''

''');
    buf.write('''

}; 

''');
  }

  return buf.toString();
}

String genClassType(DartObject root) {
  final buf = StringBuffer();
  final invocation = root.constructorInvocation;
  if (invocation == null) return '';
  final name = invocation.constructor.name ?? 'new';
  final className = invocation.constructor.enclosingElement.name ?? 'ColorGroup';

  buf.writeln('final class $className {');

  buf.writeln('const $name(');
  buf.writeAll(
    List.generate(
      invocation.positionalArguments.length,
      (index) => 'this.pos$index',
    ),
    ',',
  );
  if (invocation.positionalArguments.isNotEmpty) {
    buf.write(',');
  }

  if (invocation.namedArguments.isNotEmpty) {
    buf.write('{');
  }
  buf.writeAll(
    invocation.namedArguments.keys.map((key) => 'required this.$key'),
    ',',
  );
  if (invocation.namedArguments.isNotEmpty) {
    buf.write('}');
  }
  buf.write(');');
  buf.writeAll(
    List.generate(
      invocation.positionalArguments.length,
      (index) => 'final Color pos$index;',
    ),
    '\n',
  );
  buf.writeAll(
    invocation.namedArguments.keys.map((key) => 'final Color $key;'),
    '\n',
  );

  buf.write('}');

  return buf.toString();
}

String genClassCall(DartObject root, bool isMap) {
  final invocation = root.constructorInvocation;
  if (invocation == null) return '';
  final buf = StringBuffer();

  if (isMap) {
    if (invocation.constructor.isConst) {
      buf.write('const ');
    }
    var n = invocation.constructor.displayName;
    if (n.endsWith('.new')) {
      n = n.replaceFirst('.new', '');
    }
    buf.write(n);
  } else {
    buf.write('.${invocation.constructor.name}');
  }
  buf.write('(');
  for (var item in invocation.positionalArguments) {
    buf.write('${genColor(item)},');
  }

  for (var item in invocation.namedArguments.entries) {
    buf.write('${item.key}: ${genColor(item.value)},');
  }

  buf.write(')');

  return buf.toString();
}

List<FieldElement> getAllFields(Element e) {
  if (e case ClassElement e when e.name != 'Object') {
    final List<FieldElement> list = .from(e.fields);
    for (var item in e.allSupertypes) {
      list.addAll(getAllFields(item.element));
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
${colors.keys.isEmpty ? '' : "{"}

${colors.keys.map((e) => "required this.$e,\n").join()}

${colors.keys.isEmpty ? '' : "}"}
);

@override
$className copyWith( 
${colors.keys.isEmpty ? '' : "{"}

${colors.keys.map((e) => "Color? $e,\n").join()}

${colors.keys.isEmpty ? '' : "}"}
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
