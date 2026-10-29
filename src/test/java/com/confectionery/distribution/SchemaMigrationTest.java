package com.confectionery.distribution;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Миграции Flyway применяются к PostgreSQL 16, ограничения схемы работают. */
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class SchemaMigrationTest {

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void всеТаблицыСозданы() {
        List<String> tables = jdbc.queryForList(
                "select table_name from information_schema.tables where table_schema = 'public' and table_name <> 'flyway_schema_history'",
                String.class);
        assertThat(tables).containsExactlyInAnyOrder(
                "companies", "company_settings", "users", "regions", "routes", "route_outlets", "outlets",
                "outlet_opening_debts", "price_types", "products", "prices", "vehicles", "warehouses",
                "stock_balances", "stock_movements", "receipts", "receipt_items", "visits", "orders",
                "order_items", "order_events", "trips", "trip_orders", "deliveries", "delivery_items",
                "payments", "returns", "return_items", "cash_handovers", "gps_points", "app_events", "device_sessions",
                "order_return_items", "approvals", "login_log");
    }

    @Test
    void статусыИТелефоныПроверяютсяБазой() {
        Long company = jdbc.queryForObject("insert into companies (name, created_at) values ('Тест', now()) returning id", Long.class);
        assertThatThrownBy(() -> jdbc.update("insert into price_types (company_id, code, name) values (?, 'DISCOUNT', 'Скидка')", company))
                .isInstanceOf(DataIntegrityViolationException.class);
        assertThatThrownBy(() -> jdbc.update("insert into users (company_id, name, role, phone, created_at) values (?, 'А', 'AGENT', '87011234567', now())", company))
                .isInstanceOf(DataIntegrityViolationException.class);
        // у сотрудника компании она обязательна, у владельца — пуста
        assertThatThrownBy(() -> jdbc.update("insert into users (name, role, phone, created_at) values ('А', 'AGENT', '+77011234567', now())"))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void точкаGpsНеДублируетсяИЖурналЗнаетСвоиСобытия() {
        Long company = jdbc.queryForObject("insert into companies (name, created_at) values ('GPS', now()) returning id", Long.class);
        Long agent = jdbc.queryForObject("insert into users (company_id, name, role, phone, created_at) values (?, 'А', 'AGENT', '+77019990001', now()) returning id",
                Long.class, company);
        String point = "insert into gps_points (company_id, user_id, recorded_at, lat, lng, received_at) values (?, ?, '2026-10-27 10:00', 42.3, 69.5, now())";
        jdbc.update(point, company, agent);
        assertThatThrownBy(() -> jdbc.update(point, company, agent)).isInstanceOf(DataIntegrityViolationException.class);
        assertThatThrownBy(() -> jdbc.update("insert into app_events (company_id, uuid, user_id, event_at, kind, received_at) values (?, gen_random_uuid(), ?, now(), 'CRASH', now())",
                company, agent)).isInstanceOf(DataIntegrityViolationException.class);
        assertThatThrownBy(() -> jdbc.update("insert into company_settings (company_id, gps_interval_min) values (?, 0)", company))
                .isInstanceOf(DataIntegrityViolationException.class);
        assertThatThrownBy(() -> jdbc.update("insert into company_settings (company_id, work_start, work_end) values (?, '20:00', '08:00')", company))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void ссылкаНаЗаписьЧужойКомпанииНевозможна() {
        Long a = jdbc.queryForObject("insert into companies (name, created_at) values ('А', now()) returning id", Long.class);
        Long b = jdbc.queryForObject("insert into companies (name, created_at) values ('Б', now()) returning id", Long.class);
        Long regionOfB = jdbc.queryForObject("insert into regions (company_id, name) values (?, 'Север') returning id", Long.class, b);
        assertThatThrownBy(() -> jdbc.update("insert into routes (company_id, region_id, name) values (?, ?, 'Север-1')", a, regionOfB))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
