-- Причину возврата больше не спрашивают: торговый и экспедитор записывают только товар и штуки. У старых возвратов
-- причина остаётся, у новых — пусто.
alter table order_return_items alter column reason drop not null;
alter table return_items alter column reason drop not null;
