# clash_core

使用 hook 打包 Go 项目 [core](core)。

- Android：通过 `c-shared` 生成并打包 `libclash.so` 动态库。
- 其他平台：通过 `go build` 生成可执行文件，并作为 data asset 打包。

构建 Flutter 项目时会自动执行 `hook/build.dart`。Android 构建需要可用的
Android NDK；其他平台构建需要 `go` 命令和对应的本机 C 工具链。首次使用
data asset 前请执行 `flutter config --enable-dart-data-assets`。

