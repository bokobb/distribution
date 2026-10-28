import '../api/api_client.dart';
import 'agent_data.dart';
import 'local_store.dart';

/// Данные агента: на телефоне — для работы без сети, с сервера — при синхронизации (заменяют прежние целиком).
class AgentRepo {
  AgentRepo(this.api, this.store);

  final ApiClient api;
  final LocalStore store;

  static const _key = 'agent';

  /// Что лежит на телефоне; ещё не синхронизировались — null.
  Future<AgentData?> local() async {
    final json = await store.read(_key);
    return json == null ? null : AgentData.fromJson(json);
  }

  /// Забрать с сервера и сохранить на телефоне. Нет связи — ApiException, на телефоне всё по-прежнему.
  Future<AgentData> pull() async {
    final json = await api.agentData();
    final data = AgentData.fromJson(json);
    await store.write(_key, json);
    return data;
  }
}
