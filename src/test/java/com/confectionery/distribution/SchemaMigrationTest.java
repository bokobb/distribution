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
                "payments", "returns", "return_items", "cash_handovers");
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
    void ссылкаНаЗаписьЧужойКомпанииНевозможна() {
        Long a = jdbc.queryForObject("insert into companies (name, created_at) values ('А', now()) returning id", Long.class);
        Long b = jdbc.queryForObject("insert into companies (name, created_at) values ('Б', now()) returning id", Long.class);
        Long regionOfB = jdbc.queryForObject("insert into regions (company_id, name) values (?, 'Север') returning id", Long.class, b);
        assertThatThrownBy(() -> jdbc.update("insert into routes (company_id, region_id, name) values (?, ?, 'Север-1')", a, regionOfB))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
