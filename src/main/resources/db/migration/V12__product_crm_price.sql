-- Цена CRM: сколько производство берёт с компании за штуку — из последнего выданного заказа CRM.
-- Нужна для наценки в «Товарах и прайсе»; у товара не из CRM — пусто.
alter table products add column crm_price bigint check (crm_price >= 0);
alter table products add column crm_price_at timestamp;
