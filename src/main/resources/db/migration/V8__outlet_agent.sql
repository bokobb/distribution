-- Закрепление магазинов вместо маршрутов (design/admin, AdmAssign): у магазина свой торговый и район, без дней
-- и порядка обхода. Заказ можно оформить в любом магазине — он попадёт в продажи того, кто оформил.
-- Торговый и район переносятся из маршрута магазина. Таблицы routes и route_outlets остаются как история
-- (на них ссылаются старые визиты), новое в них не пишется.
alter table outlets
    add column agent_id  bigint,
    add column region_id bigint,
    add constraint outlets_agent_fk foreign key (agent_id, company_id) references users (id, company_id),
    add constraint outlets_region_fk foreign key (region_id, company_id) references regions (id, company_id);

update outlets o
set agent_id = r.agent_id, region_id = r.region_id
from route_outlets ro
         join routes r on r.id = ro.route_id
where ro.outlet_id = o.id;

create index outlets_agent_idx on outlets (agent_id);
create index outlets_region_idx on outlets (region_id);
