-- Приём кассы: недостача больше допуска — решение директора или владельца: на экспедитора или списать с причиной.

alter table company_settings
    add column shortage_director     boolean not null default true,
    add column shortage_to_expeditor boolean not null default true;

-- EXPEDITOR — записана на экспедитора, WRITE_OFF — списана с причиной, TOLERANCE — в пределах допуска.
alter table cash_handovers
    add column shortage_decision varchar(16) check (shortage_decision in ('EXPEDITOR', 'WRITE_OFF', 'TOLERANCE')),
    add column shortage_reason   varchar(200),
    add column decided_by        varchar(150),
    add column decided_at        timestamp;

-- до этого разница наличных всегда была на экспедиторе
update cash_handovers set shortage_decision = 'EXPEDITOR', decided_at = accepted_at where cash_diff < 0;
