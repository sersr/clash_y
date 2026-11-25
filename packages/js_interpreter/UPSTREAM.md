# 上游补丁记录（js_interpreter 0.0.5）

`packages/js_interpreter` 是 [pub.dev `js_interpreter` 0.0.5](https://pub.dev/packages/js_interpreter/versions/0.0.5) 的完整副本，只改了 `lib/src/parser/parser.dart` 一处逻辑，其余文件与上游逐字节相同（含 `pubspec.yaml`）。

根 `pubspec.yaml` 用 `dependency_overrides` 指向这个副本，所以在应用里生效的是打过补丁的解析器。

## 修改内容

上游解析器在扫描对象字面量里的 `super()` / `super.x` / `await` 时，遍历属性直接读 `prop.value`：

```dart
if (node is ObjectExpression) {
  for (final prop in node.properties) {
    if (_containsSuperCall(prop.value)) return true;  // SpreadElement 没有 value
  }
}
```

对象展开 `{...c}` 的属性是 `SpreadElement`（字段叫 `argument`），因此任何 `return {...x}` 都会抛
`NoSuchMethodError: Class 'SpreadElement' has no instance getter 'value'`。

三处都改成先判类型，展开项走 `argument`：`_containsAwait`（约 514 行）、`_containsSuperCall`（约 620 行）、`_containsSuperProperty`（约 691 行）。

```diff
     if (node is ObjectExpression) {
       for (final prop in node.properties) {
-        if (_containsSuperCall(prop.value)) return true;
+        // 展开项没有 value，只有 argument。
+        if (prop is ObjectProperty && _containsSuperCall(prop.value)) {
+          return true;
+        }
+        if (prop is SpreadElement && _containsSuperCall(prop.argument)) {
+          return true;
+        }
       }
     }
```

`lib/` 整体与上游的差异：1 个文件、19 行新增、4 行删除。

## 自行核对

```powershell
git diff --no-index --stat `
  "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\js_interpreter-0.0.5\lib" `
  "packages\js_interpreter\lib"
```

## 何时移除

上游修好这三处扫描后：升级依赖版本、删掉 `packages/js_interpreter`，并删掉根 `pubspec.yaml` 里对应的 `dependency_overrides` 条目。
