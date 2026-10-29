import 'package:distribution_mobile/app_lock.dart';

/// Отпечаток для тестов: что есть на телефоне и узнает ли он палец.
class FakeBiometrics implements Biometrics {
  FakeBiometrics({this.kind = 'отпечаток'});

  /// null — на телефоне нет ни отпечатка, ни лица.
  String? kind;
  bool answer = true;
  int asked = 0;

  @override
  Future<String?> label() async => kind;

  @override
  Future<bool> check() async {
    asked++;
    return answer;
  }
}
