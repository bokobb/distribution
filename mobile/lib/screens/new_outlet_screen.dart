import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/agent_data.dart';
import '../data/new_outlet.dart';
import '../location.dart';
import '../theme.dart';
import '../visits.dart';

/// Новый магазин от агента: название, телефон, владелец, ИП/ТОО, БИН, адрес или ориентир, прайс, маршрут,
/// точка на карте (GPS — сразу при открытии) и фото фасада. Сохраняется на телефон и уходит на сервер, где он
/// «на проверке» у оператора и сразу в маршруте агента.
class NewOutletScreen extends StatefulWidget {
  const NewOutletScreen({super.key, required this.data, required this.visits, this.routeId});

  final AgentData data;

  /// GPS, камера и отправка — те же, что у визитов.
  final VisitBook visits;

  /// Маршрут по умолчанию.
  final int? routeId;

  @override
  State<NewOutletScreen> createState() => _NewOutletScreenState();
}

class _NewOutletScreenState extends State<NewOutletScreen> {
  final _form = GlobalKey<FormState>();
  final _uuid = const Uuid().v4();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _phone2 = TextEditingController();
  final _owner = TextEditingController();
  final _legal = TextEditingController();
  final _bin = TextEditingController();
  final _address = TextEditingController();
  final _landmark = TextEditingController();
  String _price = 'WHOLESALE';
  late int? _route = widget.routeId ?? widget.data.routes.firstOrNull?.id;
  Fix? _fix;
  bool _locating = false;
  String? _photo;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _phone2, _owner, _legal, _bin, _address, _landmark]) {
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

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_text(_address) == null && _text(_landmark) == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Укажите адрес или ориентир')));
      return;
    }
    final outbox = widget.visits.outbox;
    await outbox.store.saveNewOutlet(NewOutlet(
      uuid: _uuid,
      createdAt: DateTime.now(),
      routeId: _route,
      name: _name.text.trim(),
      legal: _text(_legal),
      bin: _text(_bin),
      owner: _text(_owner),
      phone: _phone.text.trim(),
      phone2: _text(_phone2),
      address: _text(_address),
      landmark: _text(_landmark),
      lat: _fix?.lat,
      lng: _fix?.lng,
      accuracy: _fix?.accuracy,
      priceKind: _price,
      photo: _photo,
    ));
    _saved = true;
    await outbox.count();
    unawaited(outbox.flush());
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Новый магазин')),
        // не ListView: он строит только видимое, и validate() не проверил бы поля за экраном
        body: Form(
          key: _form,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              _field(_name, 'Название *', validator: (v) => v == null || v.trim().isEmpty ? 'Введите название' : null),
              _field(_phone, 'Телефон *',
                  keyboard: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Введите телефон'
                      : NewOutlet.phoneOk(v)
                          ? null
                          : '+7 и 10 цифр, например +7 701 123 45 67'),
              _field(_owner, 'Владелец'),
              _field(_legal, 'ИП / ТОО'),
              _field(_bin, 'БИН / ИИН',
                  keyboard: TextInputType.number,
                  validator: (v) => v == null || v.trim().isEmpty || RegExp(r'^\d{12}$').hasMatch(v.trim()) ? null : '12 цифр'),
              _field(_address, 'Адрес'),
              _field(_landmark, 'Ориентир (в селе вместо адреса)'),
              _field(_phone2, 'Телефон 2',
                  keyboard: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty || NewOutlet.phoneOk(v) ? null : '+7 и 10 цифр'),
              const SizedBox(height: 4),
              const Text('Прайс', style: TextStyle(color: AppColors.inkSoft)),
              Wrap(spacing: 8, children: [
                for (final (code, label) in [('WHOLESALE', 'Опт'), ('RETAIL', 'Розница')])
                  ChoiceChip(label: Text(label), selected: _price == code, onSelected: (_) => setState(() => _price = code)),
              ]),
              if (widget.data.routes.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _route,
                  decoration: const InputDecoration(labelText: 'Маршрут'),
                  items: [for (final r in widget.data.routes) DropdownMenuItem(value: r.id, child: Text(r.name))],
                  onChanged: (v) => setState(() => _route = v),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: Icon(_fix == null ? Icons.location_off_outlined : Icons.location_on_outlined,
                      color: _fix == null ? AppColors.crimson : AppColors.ok),
                  title: Text(_locating
                      ? 'Определяю, где вы…'
                      : _fix == null
                          ? 'Точка на карте не отмечена'
                          : 'Точка отмечена${_fix!.accuracy == null ? '' : ', точность ${_fix!.accuracy} м'}'),
                  subtitle: const Text('Стойте у магазина — по точке его найдёт экспедитор'),
                  trailing: TextButton(onPressed: _locating ? null : _locate, child: const Text('Ещё раз')),
                ),
              ),
              const SizedBox(height: 8),
              if (_photo != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(_photo!), height: 160, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(height: 160, child: Icon(Icons.broken_image_outlined))),
                ),
              OutlinedButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(_photo == null ? 'Фото фасада' : 'Переснять фасад'),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _locating ? null : _save, child: const Text('Сохранить магазин')),
              const SizedBox(height: 8),
              const Text('Оператор проверит магазин; до проверки в нём уже можно работать.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkSoft)),
              ],
            ),
          ),
        ),
      );

  Widget _field(TextEditingController c, String label,
          {TextInputType? keyboard, String? Function(String?)? validator}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: c,
          keyboardType: keyboard,
          textCapitalization: keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
          decoration: InputDecoration(labelText: label),
          validator: validator,
        ),
      );
}
