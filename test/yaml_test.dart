import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:process/process.dart';
import 'package:utils/utils.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('yaml format', () async {
    final response =
        await Dio().get<String>('https://free886.herokuapp.com/clash/config');
    final data = response.data;
    if (data != null) {
      Log.i('data: $data');
      final yaml = loadYaml(data);
      Log.w(yaml);
    }
  });
}
