import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../data/agent_data.dart';
import '../data/new_outlet.dart';
import '../geo.dart';
import '../location.dart';
import '../theme.dart';
import '../visits.dart';
import '../widgets/layout.dart';

/// «Новый магазин» по макету AgentNewOutlet — магазина нет в базе, торговый заполняет на месте: точка по GPS (сразу
/// при открытии, «Уточнить» — ещё раз), название на вывеске, телефон владельца, кто принимает товар, адрес и
/// ориентир, фото фасада, прайс. Сохраняется на телефон и уходит на сервер сам (там «на проверке» и в маршруте
/// агента); «Создать и оформить заказ» возвращает магазин — в нём сразу начинается заказ, без долга.
class NewOutletScreen extends StatefulWidget {
  const NewOutletScreen({super.key, required this.data, required this.visits, this.routeId});

  final AgentData data;

  /// GPS, камера и отправка — те же, что у визитов.
  final VisitBook visits;

  /// В какой маршрут агента добавить.
  final int? routeId;

  @override
  State<NewOutletScreen> createState() => _NewOutletScreenState();
}

class _NewOutletScreenState extends State<NewOutletScreen> {
  final _uuid = const Uuid().v4();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _owner = TextEditingController();
  final _address = TextEditingController();
  String _price = 'WHOLESALE';
  Fix? _fix;
  bool _locating = false;
  String? _photo;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _address]) {
      c.addListener(() => setState(() {}));
    }
    _locate();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _owner, _address]) {
      c.dispose();
    }
    // ушли без сохранения — снятое фото не нужно
    if (!_saved && _photo != null) File(_photo!).delete().ignore();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final fix = await widget.visits.location.current();
    if (mounted) {
      setState(() {
        _fix = fix ?? _fix;
        _locating = false;
      });
    }
  }

  Future<void> _takePhoto() async {
    try {
      final path = await widget.visits.camera.photo(_uuid);
      if (path == null || !mounted) return;
      final old = _photo;
      setState(() => _photo = path);
      if (old != null) File(old).delete().ignore();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть камеру')));
      }
    }
  }

  static String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  bool get _nameOk => _name.text.trim().length >= 2;
  bool get _phoneOk => NewOutlet.phoneOk(_phone.text);
  bool get _addressOk => _text(_address) != null;

  /// Чего не хватает, чтобы создать.
  List<String> get _missing => [
        if (!_nameOk) 'название',
        if (!_phoneOk) 'телефон',
        if (!_addressOk) 'адрес',
        if (_photo == null) 'фото фасада',
      ];

  /// Адрес ближайшего магазина из базы — подсказка, где стоит торговый.
  String? get _near {
    final f = _fix;
    if (f == null) return null;
    (String, int)? best;
    for (final o in widget.data.base) {
      final place = o.address ?? o.landmark;
      if (place == null || o.lat == null || o.lng == null) continue;
      final m = metersBetween(f.lat, f.lng, o.lat!, o.lng!);
      if (m <= 300 && (best == null || m < best.$2)) best = (place, m);
    }
    return best?.$1;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final outbox = widget.visits.outbox;
    final outlet = NewOutlet(
      uuid: _uuid,
      createdAt: DateTime.now(),
      routeId: widget.routeId,
      name: _name.text.trim(),
      owner: _text(_owner),
      phone: _phone.text.trim(),
      address: _text(_address),
      lat: _fix?.lat,
      lng: _fix?.lng,
      accuracy: _fix?.accuracy,
      priceKind: _price,
      photo: _photo,
    );
    await outbox.store.saveNewOutlet(outlet);
    _saved = true;
    await outbox.count();
    unawaited(outbox.flush());
    if (mounted) Navigator.pop(context, outlet.asOutlet());
  }

  @override
  Widget build(BuildContext context) {
    final missing = _missing;
    final ok = missing.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Новый магазин'),
            Text('Магазина нет в базе — заполните на месте',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.text2)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _point(),
          const SizedBox(height: 12),
          _field(_name, 'Название на вывеске *', hint: 'Например, «Береке-2»', error: _name.text.isNotEmpty && !_nameOk),
          _field(_phone, 'Телефон владельца *',
              hint: '+7 7__ ___ __ __', keyboard: TextInputType.phone, error: _phone.text.isNotEmpty && !_phoneOk),
          _field(_owner, 'Кто принимает товар', hint: 'Имя продавца или хозяина'),
          _field(_address, 'Адрес и ориентир *', hint: 'Улица, дом — напротив чего'),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _photoTile()),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Text('Цены', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.label)),
                ),
                PillTabs(
                  labels: const ['Опт', 'Розница'],
                  index: _price == 'RETAIL' ? 1 : 0,
                  onChanged: (i) => setState(() => _price = i == 1 ? 'RETAIL' : 'WHOLESALE'),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration:
                const BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.all(Radius.circular(14))),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 20, color: Color(0xFF2A21B8)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Заказ можно оформить сразу. Первый заказ нового магазина — без долга, оплата при доставке. '
                    'Руководитель проверит магазин сегодня.',
                    style: TextStyle(fontSize: 14, height: 20 / 14, color: Color(0xFF2A21B8))),
              ),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(ok ? 'Магазин сразу появится у вас, руководитель проверит' : 'Не хватает: ${missing.join(', ')}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ok ? AppColors.ok : AppColors.warn)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: ok && !_saving && !_locating ? _save : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward, size: 20),
                label: const Text('Создать и оформить заказ'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Мини-карта с точкой, точность GPS, адрес рядом и «Уточнить».
  Widget _point() {
    final f = _fix;
    final near = _near;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.all(Radius.circular(16))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (f != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 104,
              child: IgnorePointer(
                child: FlutterMap(
                  key: ValueKey((f.lat, f.lng)),
                  options: MapOptions(initialCenter: LatLng(f.lat, f.lng), initialZoom: 17),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.confectionery.distribution_mobile',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(f.lat, f.lng),
                        width: 44,
                        height: 44,
                        child: Container(
                          decoration: const BoxDecoration(color: Color(0x244136F1), shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: const Icon(Icons.storefront, size: 22, color: AppColors.accent),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(f == null ? Icons.location_off_outlined : Icons.check_circle_outline,
                      size: 16, color: f == null ? AppColors.warn : const Color(0xFF0E6B4C)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _locating
                          ? 'Определяю, где вы…'
                          : f == null
                              ? 'Точка не определена'
                              : ['Точка по GPS', if (f.accuracy != null) 'точность ${f.accuracy} м'].join(' · '),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: f == null ? AppColors.warn : const Color(0xFF0E6B4C)),
                    ),
                  ),
                ]),
                Text(
                    near != null ? 'рядом: $near' : 'Стойте у входа — по точке магазин найдёт экспедитор',
                    style: const TextStyle(fontSize: 13, color: AppColors.text2)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: _locating ? null : _locate,
            style: TextButton.styleFrom(
              backgroundColor: AppColors.fill,
              foregroundColor: AppColors.text,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
              textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: Text(f == null ? 'Ещё раз' : 'Уточнить'),
          ),
        ]),
      ]),
    );
  }

  Widget _photoTile() {
    final photo = _photo;
    if (photo == null) {
      return Material(
        color: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: Color(0xFFB4B9C2), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _takePhoto,
          child: const SizedBox(
            height: 84,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.photo_camera_outlined, color: AppColors.text),
              SizedBox(height: 6),
              Text('Фото фасада *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Переснять фасад',
      child: GestureDetector(
        onTap: _takePhoto,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 84,
            child: Stack(fit: StackFit.expand, children: [
              Image.file(File(photo),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                      color: AppColors.fill, child: Icon(Icons.storefront_outlined, color: AppColors.icon))),
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration:
                      const BoxDecoration(color: Color(0xB8101318), borderRadius: BorderRadius.all(Radius.circular(10))),
                  alignment: Alignment.center,
                  child: const Text('Фото есть',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? hint, TextInputType? keyboard, bool error = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.label)),
          ),
          TextField(
            controller: c,
            keyboardType: keyboard,
            textCapitalization: keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
            decoration: InputDecoration(
              hintText: hint,
              errorText: error ? (keyboard == null ? 'Хотя бы две буквы' : '+7 и 10 цифр, например +7 701 123 45 67') : null,
            ),
          ),
        ]),
      );
}
