import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../session.dart';
import 'home_parts.dart';

/// Главный экран экспедитора — «Рейс». Рейс, выдача и оплата появятся на этапе приложения экспедитора.
class ExpeditorHomeScreen extends StatefulWidget {
  const ExpeditorHomeScreen(
      {super.key, required this.api, required this.session, required this.onSession, required this.onLogout});

  final ApiClient api;
  final Session session;
  final ValueChanged<Session> onSession;
  final VoidCallback onLogout;

  @override
  State<ExpeditorHomeScreen> createState() => _ExpeditorHomeScreenState();
}

class _ExpeditorHomeScreenState extends State<ExpeditorHomeScreen> {
  @override
  void initState() {
    super.initState();
    checkSession(widget.api, widget.session, widget.onSession);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: homeAppBar(context, title: 'Рейс', session: widget.session, onLogout: widget.onLogout),
        body: const Center(
          child: EmptyState(
            icon: Icons.local_shipping_outlined,
            title: 'Рейс на сегодня',
            text: 'Появится здесь, когда приложение получит данные с сервера.',
          ),
        ),
      );
}
