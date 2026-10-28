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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: AppColors.chocolate,
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                        child: const Icon(Icons.local_shipping_outlined, color: AppColors.yolk, size: 30),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Дистрибуция', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Торговый агент и экспедитор', style: text.bodyLarge?.copyWith(color: AppColors.inkSoft)),
                    const SizedBox(height: 32),
                    if (widget.notice != null) ...[MessageBox.info(widget.notice!), const SizedBox(height: 16)],
                    TextFormField(
                      controller: _login,
                      decoration: const InputDecoration(labelText: 'Телефон или логин', hintText: '+7 701 000 00 00'),
                      autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Введите телефон или логин' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidden,
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        suffixIcon: IconButton(
                          tooltip: _hidden ? 'Показать пароль' : 'Скрыть пароль',
                          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hidden = !_hidden),
                        ),
                      ),
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => v == null || v.isEmpty ? 'Введите пароль' : null,
                    ),
                    if (_error != null) ...[const SizedBox(height: 16), MessageBox.error(_error!)],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Text('Войти'),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _busy ? null : _editServer,
                      icon: const Icon(Icons.dns_outlined, size: 18),
                      label: Text('Сервер: ${Uri.tryParse(widget.api.baseUrl)?.authority ?? widget.api.baseUrl}'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
