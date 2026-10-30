-- Заказ с телефона больше свободного остатка (склад минус другие неотгруженные заказы) — «Нужно разрешение»
-- с причиной STOCK; решение оператора пишется в approvals.
alter table orders drop constraint orders_hold_check;
alter table orders add constraint orders_hold_check check (hold in ('LIMIT', 'OVERDUE', 'STOCK'));
alter table approvals drop constraint approvals_kind_check;
alter table approvals add constraint approvals_kind_check check (kind in ('LIMIT', 'OVERDUE', 'UNDERPAY', 'OUTLET', 'STOCK'));
