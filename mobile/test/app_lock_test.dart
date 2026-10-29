import 'package:distribution_mobile/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_biometrics.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('при запуске закрыт; узнал — открыт; свёрнуто 10 минут — снова закрыт, меньше — нет', () async {
    var now = DateTime(2026, 10, 29, 9);
    final bio = FakeBiometrics();
    final lock = AppLock(bio, clock: () => now);
    await lock.load();
    expect([lock.locked, lock.by], [true, 'по отпечатку']);

    bio.answer = false;
    expect(await lock.unlock(), isFalse);
    expect(lock.locked, isTrue);
    bio.answer = true;
    expect(await lock.unlock(), isTrue);
    expect(lock.locked, isFalse);

    lock.hidden();
    now = now.add(const Duration(minutes: 9));
    lock.shown();
    expect(lock.locked, isFalse);
    lock.hidden();
    now = now.add(const Duration(minutes: 10));
    lock.shown();
    expect(lock.locked, isTrue);
  });

  test('выключил в «Профиле» — при запуске не закрыт; включить — сначала приложить палец', () async {
    final bio = FakeBiometrics(kind: 'лицо');
    final lock = AppLock(bio);
    await lock.load();
    expect(lock.by, 'по лицу');
    await lock.setEnabled(false);

    final again = AppLock(bio);
    await again.load();
    expect([again.enabled, again.locked], [false, false]);

    bio.answer = false;
    await again.setEnabled(true);
    expect(again.enabled, isFalse);
    bio.answer = true;
    await again.setEnabled(true);
    expect(again.enabled, isTrue);
  });

  test('на телефоне нет ни отпечатка, ни лица — замка нет', () async {
    final lock = AppLock(FakeBiometrics(kind: null));
    await lock.load();
    expect([lock.available, lock.locked], [false, false]);
  });
}
