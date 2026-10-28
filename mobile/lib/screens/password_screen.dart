import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/message_box.dart';

/// Временный пароль выдал директор — сначала свой. Правила проверяет сервер (как в админке): не короче
/// 8 знаков, не номер телефона, не как прежний.
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key, required this.api, required this.session, required this.onDone, required this.onLogout});

  final ApiClient api;
  final Session session;
  final ValueChanged<Session> onDone;
  final VoidCallback onLogout;

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
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
      widget.onDone(await widget.api.changePassword(_current.text, _password.text, _confirm.text));
    } on SessionClosedException {
      // приложение уже вернулось на вход
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Свой пароль'),
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onLogout,
            style: TextButton.styleFrom(foregroundColor: AppColors.cream),
            child: const Text('Выйти'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${widget.session.name}, придумайте свой пароль', style: text.titleLarge),
                const SizedBox(height: 8),
                const Text('Пароль, который выдал директор, — временный. Свой будете вводить на новом телефоне '
                    'или после выхода из приложения.', style: TextStyle(color: AppColors.inkSoft)),
                const SizedBox(height: 24),
                _field(_current, 'Временный пароль', (v) => v == null || v.isEmpty ? 'Введите временный пароль' : null),
                const SizedBox(height: 14),
                _field(_password, 'Новый пароль',
                    (v) => v == null || v.length < 8 ? 'Не короче 8 знаков' : null, helper: 'Не короче 8 знаков, не номер телефона'),
                const SizedBox(height: 14),
                _field(_confirm, 'Повторите новый пароль',
                    (v) => v != _password.text ? 'Пароли не совпадают' : null, done: true),
                if (_error != null) ...[const SizedBox(height: 16), MessageBox.error(_error!)],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Сохранить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, FormFieldValidator<String> validator,
          {String? helper, bool done = false}) =>
      TextFormField(
        controller: c,
        obscureText: true,
        decoration: InputDecoration(labelText: label, helperText: helper),
        textInputAction: done ? TextInputAction.done : TextInputAction.next,
        onFieldSubmitted: done ? (_) => _submit() : null,
        validator: validator,
      );
}
