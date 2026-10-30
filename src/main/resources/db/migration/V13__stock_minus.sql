-- Отгрузка не ждёт прихода: основной склад может уйти в минус, приход из CRM его закрывает.
-- Остальные склады (машины, негодный) в минус не уходят — это проверяет StockService.move.
alter table stock_balances drop constraint stock_balances_qty_check;
