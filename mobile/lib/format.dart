/// Подписи для экранов: деньги, даты, дни недели — как в админке.
library;

const weekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const weekdays = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
const monthsOf = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября',
  'ноября', 'декабря'];

/// «28 октября».
String dayMonth(DateTime d) => '${d.day} ${monthsOf[d.month - 1]}';

/// «Вторник, 28 октября» — подзаголовок главного экрана.
String dayTitle(DateTime d) => '${weekdays[d.weekday - 1]}, ${dayMonth(d)}';

/// «+77010000104» → «+7 701 000 01 04»; другой вид — как есть.
String phoneText(String phone) {
  final m = RegExp(r'^\+7(\d{3})(\d{3})(\d{2})(\d{2})$').firstMatch(phone);
  return m == null ? phone : '+7 ${m[1]} ${m[2]} ${m[3]} ${m[4]}';
}

/// 30000 → «30 000» — разряды через неразрывный пробел, без знака валюты (для таблиц).
String amount(int v) {
  final digits = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
    b.write(digits[i]);
  }
  return '${v < 0 ? '−' : ''}$b';
}

/// 30000 → «30 000 ₸»; минус — «−5 000 ₸».
String money(int v) => '${amount(v)} ₸';

String two(int n) => n.toString().padLeft(2, '0');

/// «08:42».
String time(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

/// «28.10.2026».
String date(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';

/// «сегодня в 10:55», «вчера в 18:02», «26.10 в 09:15».
String when(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return 'сегодня в ${time(t)}';
  if (day == today.subtract(const Duration(days: 1))) return 'вчера в ${time(t)}';
  return '${two(t.day)}.${two(t.month)} в ${time(t)}';
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

/// Сумма прописью для накладной, как в админке (до 999 миллиардов): 112440 → «Сто двенадцать тысяч четыреста сорок
/// тенге».
String moneyWords(int amount) {
  if (amount == 0) return 'Ноль тенге';
  const ones = ['', 'один', 'два', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
  const onesF = ['', 'одна', 'две', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
  const teens = ['десять', 'одиннадцать', 'двенадцать', 'тринадцать', 'четырнадцать', 'пятнадцать', 'шестнадцать',
    'семнадцать', 'восемнадцать', 'девятнадцать'];
  const tens = ['', '', 'двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят', 'семьдесят', 'восемьдесят',
    'девяносто'];
  const hundreds = ['', 'сто', 'двести', 'триста', 'четыреста', 'пятьсот', 'шестьсот', 'семьсот', 'восемьсот',
    'девятьсот'];
  // разряды от старшего: миллиарды, миллионы, тысячи (женский род), единицы
  const scales = [
    ['миллиард', 'миллиарда', 'миллиардов'],
    ['миллион', 'миллиона', 'миллионов'],
    ['тысяча', 'тысячи', 'тысяч'],
    null,
  ];
  final words = <String>[if (amount < 0) 'минус'];
  final n = amount.abs();
  var scale = 1000000000;
  for (var i = 0; i < scales.length; i++, scale ~/= 1000) {
    final part = n ~/ scale % 1000;
    if (part == 0) continue;
    if (part ~/ 100 > 0) words.add(hundreds[part ~/ 100]);
    final rest = part % 100;
    if (rest >= 10 && rest < 20) {
      words.add(teens[rest - 10]);
    } else {
      if (rest ~/ 10 > 0) words.add(tens[rest ~/ 10]);
      if (rest % 10 > 0) words.add((i == 2 ? onesF : ones)[rest % 10]);
    }
    final forms = scales[i];
    if (forms != null) {
      final a = part % 100, b = a % 10;
      words.add(a > 10 && a < 20 ? forms[2] : b == 1 ? forms[0] : b >= 2 && b <= 4 ? forms[1] : forms[2]);
    }
  }
  final s = '${words.join(' ')} тенге';
  return s[0].toUpperCase() + s.substring(1);
}
