-- Рабочее время компании: торговый или экспедитор открыл приложение в это время — рабочий день начинается сам
-- (без «Начать день»), в конце — заканчивается сам. Вне этого времени день начинают кнопкой.
alter table company_settings
    add column work_start time not null default '08:00',
    add column work_end   time not null default '20:00',
    add constraint company_settings_work_hours check (work_start < work_end);
