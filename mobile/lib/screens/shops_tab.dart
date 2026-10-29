import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../visits.dart';
import '../workday.dart';
import 'shops_list.dart';
import 'shops_map.dart';

/// Вкладка «Магазины» торгового: карта всей базы (AgentShopsMap) или список (AgentRoute) — «Список» / «Карта».
class ShopsTab extends StatefulWidget {
  const ShopsTab({super.key, required this.data, required this.visits, required this.workday});

  final AgentData data;
  final VisitBook visits;
  final Workday workday;

  @override
  State<ShopsTab> createState() => _ShopsTabState();
}

class _ShopsTabState extends State<ShopsTab> {
  bool _list = false;

  @override
  Widget build(BuildContext context) => _list
      ? ShopsList(
          data: widget.data, visits: widget.visits, workday: widget.workday, onMap: () => setState(() => _list = false))
      : ShopsMap(
          data: widget.data, visits: widget.visits, workday: widget.workday, onList: () => setState(() => _list = true));
}
