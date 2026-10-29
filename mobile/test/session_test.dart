import 'package:distribution_mobile/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('адрес сервера, сменённый в этой сборке, держится', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SessionStore();

    await store.setServerUrl('http://192.168.1.5:8090');

    expect(await store.serverUrl(), 'http://192.168.1.5:8090');
  });

  test('адрес из старой сборки сбрасывается на адрес новой', () async {
    // старая сборка сохраняла только адрес
    SharedPreferences.setMockInitialValues({'server.url': 'http://192.168.1.5:8090'});
    final store = SessionStore();

    expect(await store.serverUrl(), SessionStore.defaultServer);
    expect((await SharedPreferences.getInstance()).getString('server.url'), isNull);
  });

  test('адрес, сменённый в сборке с другим адресом по умолчанию, сбрасывается', () async {
    SharedPreferences.setMockInitialValues(
        {'server.url': 'http://192.168.1.5:8090', 'server.urlFor': 'https://другой.сервер'});

    expect(await SessionStore().serverUrl(), SessionStore.defaultServer);
  });
}
