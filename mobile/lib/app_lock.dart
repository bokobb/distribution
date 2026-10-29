import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Отпечаток или лицо — системное окно телефона. В тестах — подставное.
abstract class Biometrics {
  /// «отпечаток», «лицо», «отпечаток или лицо»; на телефоне нет ни того, ни другого (или не настроено) — null.
  Future<String?> label();

  /// Показать системное окно; true — телефон узнал человека (или он ввёл PIN-код телефона).
  Future<bool> check();
}

/// Настоящее окно local_auth. Не узнало палец или лицо — можно ввести PIN-код (графический ключ) телефона.
class DeviceBiometrics implements Biometrics {
  final _auth = LocalAuthentication();

  /// Телефон не ответил за 3 с — считаем, что нечем: лучше без замка, чем пустой экран.
  @override
  Future<String?> label() => _label().timeout(const Duration(seconds: 3), onTimeout: () => null);

  Future<String?> _label() async {
    try {
      if (!await _auth.isDeviceSupported() || !await _auth.canCheckBiometrics) return null;
      final types = await _auth.getAvailableBiometrics();
      if (types.isEmpty) return null;
      final face = types.contains(BiometricType.face);
      final finger = types.contains(BiometricType.fingerprint);
      if (face && !finger) return 'лицо';
      if (face && finger) return 'отпечаток или лицо';
      return 'отпечаток';
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> check() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Вход в «Дистрибуцию»',
        // false — лицо узнало, «Подтвердить» нажимать не нужно (на отпечаток не влияет)
        sensitiveTransaction: false,
        persistAcrossBackgrounding: true,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Вход в «Дистрибуцию»',
            signInHint: 'Приложите палец или посмотрите на экран',
            cancelButton: 'Отмена',
          ),
        ],
      );
    } catch (_) {
      return false;
    }
  }
}

/// Без отпечатка и лица — замка нет (тесты, где замок не проверяется).
class NoBiometrics implements Biometrics {
  const NoBiometrics();

  @override
  Future<String?> label() async => null;

  @override
  Future<bool> check() async => false;
}

/// Замок приложения. Пароль сотрудник вводит один раз — дальше вход держит ключ устройства, а открыть приложение —
/// отпечатком или лицом: при запуске и если оно было свёрнуто дольше [idle]. Включён сам, если на телефоне
/// настроен отпечаток или лицо; выключается в «Профиле». Всё — только на телефоне, сервер об этом не знает.
class AppLock extends ChangeNotifier {
  AppLock(this.bio, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final Biometrics bio;
  final DateTime Function() _now;

  static const idle = Duration(minutes: 10);
  static const _key = 'lock.bio';

  /// Чем входить: «отпечаток», «лицо»; на телефоне нечем — null, замка нет.
  String? label;
  bool enabled = true;

  /// Приложение закрыто замком.
  bool locked = false;

  /// Идёт системное окно.
  bool checking = false;

  DateTime? _hiddenAt;

  bool get available => label != null;

  /// «по отпечатку», «по лицу», «по отпечатку или лицу» — для «Войти …» и «Вход …».
  String get by => switch (label) {
        'лицо' => 'по лицу',
        'отпечаток или лицо' => 'по отпечатку или лицу',
        _ => 'по отпечатку',
      };

  /// При запуске: чем входить и включён ли замок; включён — сразу закрыть.
  Future<void> load() async {
    label = await bio.label();
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_key) ?? true;
    locked = available && enabled;
    notifyListeners();
  }

  /// Приложение свернули.
  void hidden() => _hiddenAt ??= _now();

  /// Вернулись: свёрнуто было дольше [idle] — закрыть.
  void shown() {
    final at = _hiddenAt;
    _hiddenAt = null;
    if (at != null && available && enabled && _now().difference(at) >= idle) {
      locked = true;
      notifyListeners();
    }
  }

  /// Вошёл сотрудник с паролем — пароль только что проверен, замок не нужен.
  void open() {
    locked = false;
    notifyListeners();
  }

  /// Системное окно; узнало — открыть.
  Future<bool> unlock() async {
    if (checking) return false;
    checking = true;
    notifyListeners();
    final ok = await bio.check();
    checking = false;
    if (ok) locked = false;
    notifyListeners();
    return ok;
  }

  /// Включить (сначала приложить палец — убедиться, что работает) или выключить.
  Future<void> setEnabled(bool on) async {
    if (on && !await bio.check()) return;
    enabled = on;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, on);
    notifyListeners();
  }
}

/// Замок для экранов ниже: «Профиль» включает и выключает вход по отпечатку.
class AppLockScope extends InheritedNotifier<AppLock> {
  const AppLockScope({super.key, required AppLock lock, required super.child}) : super(notifier: lock);

  static AppLock? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppLockScope>()?.notifier;
}
