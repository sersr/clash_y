import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:app_colors/app_colors.dart';
import 'package:app_colors/src/base_builder.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

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
        final colors = value.getField('colors');

        final className =
            value.getField('className')?.toStringValue() ?? 'AppColors';
        final genAno = value.getField('genAnother')?.toBoolValue() ?? false;

        if (colors == null) continue;

        var isMap = false;
        var fields = <(String?, DartObject?)>[];
        if (colors.toMapValue() case var colors?) {
          for (var item in colors.entries) {
            fields.add((item.key?.toStringValue(), item.value));
          }
          isMap = true;
        } else {
          fields = (colors.type!.element! as ClassElement).fields
              .where((e) => e.name != 'hashCode')
              .map((e) => (e.name, colors.getField(e.name ?? '')))
              .toList();

          isMap = false;
        }

        return genRoot(className, fields, isMap, genAno);
      }
    }
  }
}

Builder appColorsBuilder(BuilderOptions options) =>
    SharedPartBuilder([AppColorsGeneratorForAnnotation()], 'app_colors');
