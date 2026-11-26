# scripts

- clean

## clean

```sh
dart run tools/bin/clean.dart [cache] [dry]
```

删除构建残留：

- `packages/*/build`、`packages/*/.build`
- Android 打包用的 native 拷贝：`build/app/intermediates/flutter/<variant>/native_assets`、
  `build/app/generated/jniLibs`、`merged_native_libs`、`merged_jni_libs`、`stripped_native_libs`
- `.dart_tool/hooks_runner/shared/*/build` 里除最新一次外的旧构建

参数：

- 无参数：清完上面的目录后再跑一次 `flutter clean`
- `cache`：跳过 `flutter clean`，只清上面的目录。改完 Go core 后重编 APK 前用这个，
  否则 Gradle 可能沿用旧的 `libclash.so`，App 里跑的还是上一版核心
- `dry`：只打印将要删除的目录和体积，不实际删除
