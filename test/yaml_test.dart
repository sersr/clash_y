// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:common/common.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nop/utils.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('yaml format', () async {
    final response = await Dio().get<String>(
      'https://free886.herokuapp.com/clash/config',
    );
    final data = response.data;
    if (data != null) {
      Log.i('data: $data');
      final yaml = loadYaml(data);
      Log.w(yaml);
    }
  });

  test('json to yaml', () {
    final j = {"hello": "world"};

    final y = YamlUtils.edit(jsonEncode(j));
    print(y.toString());
  });
}
