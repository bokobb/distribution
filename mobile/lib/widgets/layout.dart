import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
            // подпись шире значения: «Невыданный товар — на склад · 29 шт» в одну строку
            Expanded(flex: 3, child: Text(label)),
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 8),
            ],
            if (value != null)
              Flexible(
                flex: 2,
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

/// Переключатель из двух-трёх вариантов на серой подложке, выбранный — белый («Новые · 9 / Доставлены · 5»).
class PillTabs extends StatelessWidget {
  const PillTabs({super.key, required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(color: Color(0xFFE9EBEF), borderRadius: BorderRadius.all(Radius.circular(12))),
        child: Row(
          children: [
            for (final (i, label) in labels.indexed) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: Semantics(
                  selected: i == index,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == index ? AppColors.card : Colors.transparent,
                        borderRadius: const BorderRadius.all(Radius.circular(9)),
                        boxShadow: i == index
                            ? const [BoxShadow(color: Color(0x24101318), blurRadius: 3, offset: Offset(0, 1))]
                            : null,
                      ),
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: i == index ? AppColors.text : AppColors.text2)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}

/// Небольшая метка в строке: «Наличные», «В долг», «Частично».
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = AppColors.label, this.background = AppColors.fill});

  /// Янтарная — долг, частично.
  const Tag.warn(this.text, {super.key})
      : color = const Color(0xFF8A5000),
        background = AppColors.warnBg;

  /// Красная — отказ.
  const Tag.err(this.text, {super.key})
      : color = const Color(0xFFA3241A),
        background = AppColors.errBg;

  /// Зелёная — был сегодня, заказ.
  const Tag.ok(this.text, {super.key})
      : color = const Color(0xFF0E6B4C),
        background = AppColors.okBg;

  /// Фирменная — новый, на проверке, ждёт руководителя.
  const Tag.brand(this.text, {super.key})
      : color = AppColors.accentPressed,
        background = AppColors.accentSoft;

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: background, borderRadius: const BorderRadius.all(Radius.circular(6))),
        // по ширине текста и в Wrap, где ширина ограничена
        child: Center(
            widthFactor: 1,
            child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
      );
}

/// Поле суммы в тенге: крупные цифры, «₸» и кнопка справа («Вся сумма», «Весь долг»).
class MoneyInput extends StatelessWidget {
  const MoneyInput(
      {super.key,
      required this.controller,
      required this.fillLabel,
      required this.onFill,
      this.onChanged,
      this.strong = true,
      this.semanticLabel});

  final TextEditingController controller;
  final String fillLabel;
  final VoidCallback onFill;
  final VoidCallback? onChanged;

  /// Главное поле карточки — индиго рамка и цифры крупнее.
  final bool strong;

  /// Что это за сумма — для чтения с экрана (подпись видна над полем).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final size = strong ? 22.0 : 20.0;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(strong ? 14 : 12)),
      borderSide: strong
          ? const BorderSide(color: AppColors.accent, width: 2)
          : const BorderSide(color: Color(0xFFD5D9E0)),
    );
    return Semantics(
      label: semanticLabel,
      child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
      onChanged: (_) => onChanged?.call(),
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, fontFeatures: tabular),
      decoration: InputDecoration(
        hintText: '0',
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: strong ? 16 : 14),
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('₸', style: TextStyle(fontSize: size - 2, fontWeight: FontWeight.w600, color: AppColors.icon)),
              const SizedBox(width: 10),
              TextButton(
                onPressed: onFill,
                style: TextButton.styleFrom(
                  backgroundColor: strong ? AppColors.accentSoft : AppColors.fill,
                  foregroundColor: strong ? AppColors.accentPressed : AppColors.text,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: Text(fillLabel),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Кружок с буквами товара («ПО» — «Печенье овсяное»), цвет — по товару, как в макетах заказа.
class ProductAvatar extends StatelessWidget {
  const ProductAvatar({super.key, required this.id, required this.name});

  final int id;
  final String name;

  static const _colors = [
    (Color(0xFFFDE9DA), Color(0xFF9A4B12)),
    (Color(0xFFFCE4EC), Color(0xFF9C2752)),
    (Color(0xFFFFF1CC), Color(0xFF8A6100)),
    (Color(0xFFE8F0FE), Color(0xFF2B5BA8)),
    (Color(0xFFEDE7FF), Color(0xFF5B3FB3)),
    (Color(0xFFE6F4EA), Color(0xFF1E7A46)),
    (Color(0xFFE3F1FF), Color(0xFF1F5C99)),
    (Color(0xFFF3E8E2), Color(0xFF7A4A2E)),
  ];

  /// Первые буквы двух первых слов.
  static String initials(String name) {
    final words = name.split(RegExp(r'[^0-9A-Za-zА-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІі]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return [for (final w in words.take(2)) w[0]].join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors[id % _colors.length];
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(initials(name), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}

/// Количество на серой «таблетке» с белыми круглыми кнопками: «−  2 кор  +». Последнюю убрать — корзина красным.
class PillStepper extends StatelessWidget {
  const PillStepper(
      {super.key,
      required this.text,
      required this.onDec,
      required this.onInc,
      required this.decLabel,
      required this.incLabel,
      this.removes = false,
      this.onText,
      this.large = false});

  final String text;
  final VoidCallback? onDec;
  final VoidCallback? onInc;
  final String decLabel;
  final String incLabel;

  /// Минус уберёт строку — вместо минуса корзина.
  final bool removes;

  /// Нажали на число — ввести вручную.
  final VoidCallback? onText;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final button = large ? 36.0 : 30.0;
    Widget round(IconData icon, Color color, VoidCallback? onTap, String label) => Semantics(
          button: true,
          label: label,
          child: Tooltip(
            message: label,
            child: InkResponse(
              onTap: onTap,
              radius: button,
              child: Container(
                width: button,
                height: button,
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x1A101318), blurRadius: 2, offset: Offset(0, 1))],
                ),
                child: Icon(icon, size: large ? 20 : 18, color: onTap == null ? const Color(0xFFC9CDD5) : color),
              ),
            ),
          ),
        );
    return Container(
      height: large ? 48 : 40,
      padding: EdgeInsets.symmetric(horizontal: large ? 5 : 4),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.all(Radius.circular(large ? 24 : 20)),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          round(removes ? Icons.delete_outline : Icons.remove, removes ? AppColors.err : AppColors.text, onDec, decLabel),
          GestureDetector(
            onTap: onText,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: large ? 64 : 46),
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: large ? 17 : 14, fontWeight: FontWeight.w700, fontFeatures: tabular)),
            ),
          ),
          round(Icons.add, AppColors.text, onInc, incLabel),
        ],
      ),
    );
  }
}
