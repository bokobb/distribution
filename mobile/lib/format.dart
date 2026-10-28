/// Подписи для экранов: деньги, даты, дни недели — как в админке.
library;

const weekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// 30000 → «30 000 ₸»; минус — «−5 000 ₸».
String money(int amount) {
  final digits = amount.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
    b.write(digits[i]);
  }
  return '${amount < 0 ? '−' : ''}$b ₸';
}

String two(int n) => n.toString().padLeft(2, '0');

/// «28.10.2026».
String date(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';

/// «сегодня в 10:55», «вчера в 18:02», «26.10 в 09:15».
String when(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final time = '${two(t.hour)}:${two(t.minute)}';
  if (day == today) return 'сегодня в $time';
  if (day == today.subtract(const Duration(days: 1))) return 'вчера в $time';
  return '${two(t.day)}.${two(t.month)} в $time';
}

/// «1 магазин», «3 магазина», «12 магазинов».
String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  final word = m10 == 1 && m100 != 11
      ? one
      : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)
          ? few
          : many;
  return '$n $word';
}
