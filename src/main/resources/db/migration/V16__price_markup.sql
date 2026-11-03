-- С 04.11.2026 у товара одна цена продажи (опт = розница) и наценка над ценой CRM, %: ею «Поставить всем» в «Товарах»
-- считает цены, и с ней новый товар из CRM получает цену сам (раньше — 0 ₸, пока не проставят).
alter table company_settings
    add column price_markup int not null default 20,
    add constraint company_settings_price_markup check (price_markup between 0 and 500);
