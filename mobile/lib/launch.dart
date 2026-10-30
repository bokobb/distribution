import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Позвонить: открывает набор номера с этим телефоном.
Future<void> call(BuildContext context, String phone) =>
    _open(context, Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), '')), 'Не удалось открыть звонок');

/// Маршрут до магазина: телефон предложит карты (2ГИС, Яндекс, Google). Нет точки — ищем по адресу.
Future<void> route(BuildContext context, {double? lat, double? lng, required String name, String? address}) {
  final uri = lat != null && lng != null
      ? Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(name)})')
      : Uri.parse('geo:0,0?q=${Uri.encodeComponent(address ?? name)}');
  return _open(context, uri, 'На телефоне нет приложения карт');
}

/// Сколько точек 2ГИС строит в одном маршруте — вместе с началом.
const gisMaxPoints = 10;

/// Весь маршрут в 2ГИС: точки (широта, долгота) по порядку — первая начало. Ссылка 2gis.kz откроет приложение 2ГИС,
/// если оно стоит, иначе сайт; точек больше [gisMaxPoints] 2ГИС не принимает — лишние отбрасываются.
Future<void> routeAll(BuildContext context, List<(double, double)> points) {
  final path = points.take(gisMaxPoints).map((p) => '${p.$2},${p.$1}').join('|');
  return _open(context, Uri.parse('https://2gis.kz/shymkent/directions/points/$path'), 'Не удалось открыть 2ГИС');
}

Future<void> _open(BuildContext context, Uri uri, String problem) async {
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Exception {
    ok = false;
  }
  if (!ok && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
}
