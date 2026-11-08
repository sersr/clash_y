import 'package:install_apps/install_apps.dart';
import 'package:test/test.dart';

void main() {
  test('installed application exposes package selection metadata', () {
    final app = InstalledApplication(
      appName: 'Clashy',
      packageName: 'io.aote.clashy',
      systemApp: false,
      hasInternetPermission: true,
    );

    expect(app.appName, 'Clashy');
    expect(app.packageName, 'io.aote.clashy');
    expect(app.systemApp, isFalse);
    expect(app.hasInternetPermission, isTrue);
  });
}
