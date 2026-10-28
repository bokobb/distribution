import '../api/api_client.dart';
import 'expeditor_data.dart';
import 'local_store.dart';

/// Данные экспедитора: на телефоне (SQLite) и с сервера. Экран сразу показывает телефонные, потом обновляет.
class ExpeditorRepo {
  ExpeditorRepo(this.api, this.store);

  final ApiClient api;
  final LocalStore store;

  static const _key = 'expeditor';

  /// Что лежит на телефоне; ещё не синхронизировались — null.
  Future<ExpeditorData?> local() async {
    final json = await store.read(_key);
    return json == null ? null : ExpeditorData.fromJson(json);
  }

  /// Забрать с сервера и сохранить на телефоне. Нет связи — ApiException, на телефоне всё по-прежнему.
  Future<ExpeditorData> pull() async {
    final json = await api.expeditorData();
    final data = ExpeditorData.fromJson(json);
    await store.write(_key, json);
    return data;
  }
}
