import 'package:flutter/material.dart';

import '../theme.dart';

/// Шапка раздела, как в макетах: крупный заголовок 28/34, под ним подпись (день, машина), справа — кнопки.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing = const []});

  final String title;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.headlineMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: text.bodyMedium!.copyWith(color: AppColors.text2)),
                ],
              ],
            ),
          ),
          for (final w in trailing) Padding(padding: const EdgeInsets.only(left: 8, top: 2), child: w),
        ],
      ),
    );
  }
}

/// Белая карточка со строками через тонкую линию (как «Машина / Рабочий день / GPS» в профиле).
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final (i, c) in children.indexed) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 0),
                c,
              ],
            ],
          ),
        ),
      );
}

/// Строка карточки: слева подпись, справа значение (с точкой статуса); можно нажать — тогда стрелка.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, this.value, this.dot, this.onTap});

  final String label;
  final String? value;

  /// Цвет точки перед значением: GPS включён — зелёная.
  final Color? dot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, onTap != null ? 12 : 16, 8),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 8),
            ],
            if (value != null)
              Flexible(
                child: Text(value!, textAlign: TextAlign.end, style: const TextStyle(color: AppColors.text2)),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.icon),
            ],
          ],
        ),
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// Пункт нижнего меню.
class TabItem {
  const TabItem(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Нижнее меню разделов: белое, линия сверху, выбранный — индиго.
class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.items, required this.index, required this.onTap});

  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                for (final (i, item) in items.indexed)
                  Expanded(
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      child: InkResponse(
                        onTap: () => onTap(i),
                        containedInkWell: true,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(i == index ? item.selectedIcon : item.icon,
                                size: 24, color: i == index ? AppColors.accent : AppColors.text2),
                            const SizedBox(height: 4),
                            Text(item.label,
                                style: TextStyle(
                                    fontSize: 11,
                                    height: 14 / 11,
                                    fontWeight: FontWeight.w600,
                                    color: i == index ? AppColors.accent : AppColors.text2)),
                          ],
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

/// Главный экран роли: разделы снизу, каждый со своей прокруткой; переключение не теряет место в списке. Раздел
/// строится, когда его первый раз открыли (карта не грузится, пока её не смотрели).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.tabs, required this.pages, this.index, this.onIndex});

  final List<TabItem> tabs;
  final List<Widget> pages;

  /// Раздел задаёт хозяин (например, «Перейти к сдаче кассы»); null — помнит сам.
  final int? index;
  final ValueChanged<int>? onIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _opened = <int>{};

  @override
  Widget build(BuildContext context) {
    final index = widget.index ?? _index;
    _opened.add(index);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: index,
          children: [
            for (final (i, page) in widget.pages.indexed) _opened.contains(i) ? page : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: AppTabBar(
        items: widget.tabs,
        index: index,
        onTap: (i) {
          setState(() => _index = i);
          widget.onIndex?.call(i);
        },
      ),
    );
  }
}
