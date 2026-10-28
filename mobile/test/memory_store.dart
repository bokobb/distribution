import 'package:distribution_mobile/data/local_store.dart';

/// Хранилище в памяти — вместо SQLite в тестах экранов.
class MemoryStore implements LocalStore {
  final data = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> read(String key) async => data[key];

  @override
  Future<void> write(String key, Map<String, dynamic> json) async => data[key] = json;

  @override
  Future<void> clear() async => data.clear();
}
