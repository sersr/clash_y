
import 'package:shelf_router/shelf_router.dart';

import '../server.dart';

extension type MyRouter._(Router _) implements Router {
  factory MyRouter() => ._(.new());

  void get(String route, RespHandler handler) => add('GET', route, handler);

  /// Handle `HEAD` request to [route] using [handler].
  void head(String route, RespHandler handler) => add('HEAD', route, handler);

  /// Handle `POST` request to [route] using [handler].
  void post(String route, RespHandler handler) => add('POST', route, handler);

  /// Handle `PUT` request to [route] using [handler].
  void put(String route, RespHandler handler) => add('PUT', route, handler);

  /// Handle `DELETE` request to [route] using [handler].
  void delete(String route, RespHandler handler) =>
      add('DELETE', route, handler);
  void ws(String route, Function handler) => add('GET', route, handler);
}
