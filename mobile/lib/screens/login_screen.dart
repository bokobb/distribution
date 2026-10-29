import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/message_box.dart';

/// Вход: телефон (в любом виде — сервер сам приведёт) или логин и пароль. Внизу — адрес сервера.
/// notice — почему снова вход («Вход на этом телефоне закрыт…»).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.store, required this.onLogin, this.notice});

  final ApiClient api;
  final SessionStore store;
  final ValueChanged<Session> onLogin;
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.onLogin(await widget.api.login(_login.text.trim(), _password.text));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editServer() async {
    final url = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ServerSheet(initial: widget.api.baseUrl),
    );
    if (url == null) return;
    await widget.store.setServerUrl(url);
    setState(() => widget.api.baseUrl = url);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final version = widget.api.appVersion?.split('+').first;
    return Scaffold(
      backgroundColor: AppColors.card,
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Hero(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Дистрибуция', style: text.headlineLarge),
                          const SizedBox(height: 6),
                          Text('Вход для экспедиторов и торговых агентов',
                              style: text.bodyMedium!.copyWith(color: AppColors.text2)),
                          const SizedBox(height: 24),
                          if (widget.notice != null) ...[MessageBox.info(widget.notice!), const SizedBox(height: 16)],
                          _label('Телефон'),
                          TextFormField(
                            controller: _login,
                            keyboardType: TextInputType.phone,
                            style: _input,
                            decoration: const InputDecoration(hintText: '+7 701 000 00 00'),
                            autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            validator: (v) => v == null || v.trim().isEmpty ? 'Введите телефон' : null,
                          ),
                          const SizedBox(height: 14),
                          _label('Пароль'),
                          TextFormField(
                            controller: _password,
                            obscureText: _hidden,
                            style: _input,
                            decoration: InputDecoration(
                              suffixIcon: IconButton(
                                tooltip: _hidden ? 'Показать пароль' : 'Скрыть пароль',
                                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    color: AppColors.text2),
                                onPressed: () => setState(() => _hidden = !_hidden),
                              ),
                            ),
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            validator: (v) => v == null || v.isEmpty ? 'Введите пароль' : null,
                          ),
                          if (_error != null) ...[const SizedBox(height: 16), MessageBox.error(_error!)],
                          const SizedBox(height: 20),
                          FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                : const Text('Войти'),
                          ),
                          const SizedBox(height: 24),
                          Text(
                              'Первый пароль выдаёт руководитель — после входа придумаете свой. Забыли пароль? '
                              'Попросите новый у руководителя.',
                              style: const TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.text2)),
                          const SizedBox(height: 32),
                          // Версия и сервер внизу; сервер меняют только для проверки — нажать на строку.
                          InkWell(
                            onTap: _busy ? null : _editServer,
                            borderRadius: const BorderRadius.all(Radius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                [
                                  if (version != null) 'Версия $version',
                                  'сервер ${Uri.tryParse(widget.api.baseUrl)?.authority ?? widget.api.baseUrl}',
                                ].join(' · '),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13, color: AppColors.text2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _input = TextStyle(fontSize: 17, fontWeight: FontWeight.w500, fontFeatures: tabular);

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium),
      );
}

/// Шапка входа: светлая подложка с пунктиром маршрута и знак приложения.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 300,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFFF5F4FF), child: CustomPaint(painter: _RoutePainter()))),
            Positioned(
              left: 24,
              top: 72,
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  boxShadow: [BoxShadow(color: Color(0x664136F1), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -10)],
                ),
                child: const Icon(Icons.route, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      );
}

/// Путь из макета (390 × 300): широкая светлая линия, по ней точки, кружки остановок.
class _RoutePainter extends CustomPainter {
  const _RoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 390;
    Offset p(double x, double y) => Offset(x * k, y);
    final a = p(-10, 250), c1 = p(60, 250), c2 = p(70, 170), b = p(140, 170);
    final c3 = p(210, 170), c4 = p(230, 230), c = p(280, 160);
    final c5 = p(330, 90), c6 = p(340, 70), d = p(400, 70);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy)
      ..cubicTo(c3.dx, c3.dy, c4.dx, c4.dy, c.dx, c.dy)
      ..cubicTo(c5.dx, c5.dy, c6.dx, c6.dy, d.dx, d.dy);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFDCD9FD));
    final dot = Paint()..color = const Color(0xFF8E87F7);
    for (final m in path.computeMetrics()) {
      for (var t = 0.0; t < m.length; t += 8) {
        final pos = m.getTangentForOffset(t)?.position;
        if (pos != null) canvas.drawCircle(pos, 1.1, dot);
      }
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppColors.accent;
    for (final o in [b, c]) {
      canvas.drawCircle(o, 7, Paint()..color = Colors.white);
      canvas.drawCircle(o, 7, ring);
    }
    final end = p(355, 79);
    canvas.drawCircle(end, 10.5, Paint()..color = Colors.white);
    canvas.drawCircle(end, 9, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Адрес сервера: https://… или http://… для разработки. Возвращает адрес без «/» в конце.
class _ServerSheet extends StatefulWidget {
  const _ServerSheet({required this.initial});

  final String initial;

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late final _url = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _save() {
    var url = _url.text.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
      setState(() => _error = 'Адрес начинается с https:// или http://');
      return;
    }
    Navigator.pop(context, url);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Адрес сервера', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(errorText: _error),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Сохранить')),
        ],
      ),
    );
  }
}
