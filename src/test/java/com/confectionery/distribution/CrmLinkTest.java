package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.service.Actor;
import com.confectionery.distribution.service.CrmSync;
import com.confectionery.distribution.service.StockService;
import com.confectionery.distribution.tenant.TenantContext;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.support.TransactionTemplate;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Связь с CRM: обмен с поддельной CRM (компании, отгрузки → приходы, принятые приходы → CRM) и вход владельца по пропуску. */
@SpringBootTest(properties = {"distribution.crm.key=test-key", "distribution.crm.sync-delay-ms=3600000"})
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class CrmLinkTest {

    private static final String KEY = "test-key";
    private static final HttpServer CRM;
    private static final List<String> CALLS = new CopyOnWriteArrayList<>();
    private static volatile String shipments = "[]";

    static {
        try {
            CRM = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
        CRM.createContext("/api/distribution/", CrmLinkTest::answer);
        CRM.start();
    }

    @DynamicPropertySource
    static void crm(DynamicPropertyRegistry r) {
        r.add("distribution.crm.url", () -> "http://127.0.0.1:" + CRM.getAddress().getPort());
    }

    @AfterAll
    static void stop() {
        CRM.stop(0);
    }

    /** Поддельная CRM: запоминает запросы «МЕТОД путь тело», отвечает списком клиентов и отгрузками. */
    private static void answer(HttpExchange ex) throws IOException {
        String body = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        String path = ex.getRequestURI().getPath().replace("/api/distribution", "");
        if (!KEY.equals(ex.getRequestHeaders().getFirst("X-Dist-Key"))) {
            ex.sendResponseHeaders(401, -1);
            ex.close();
            return;
        }
        CALLS.add(ex.getRequestMethod() + " " + path + " " + body);
        String out = switch (path) {
            case "/clients" -> "[{\"id\": 501, \"name\": \"ТОО «Дилер CRM»\", \"phone\": \"+77015550101\"}]";
            case "/shipments" -> shipments;
            default -> "{\"status\": \"ok\"}";
        };
        byte[] bytes = out.getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().add("Content-Type", "application/json");
        ex.sendResponseHeaders(200, bytes.length);
        ex.getResponseBody().write(bytes);
        ex.close();
    }

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;
    @Autowired
    CrmSync sync;
    @Autowired
    StockService stock;
    @Autowired
    TransactionTemplate tx;

    @Test
    void отгрузкаCrm_приходНаСклад_принятоеУходитВCrm() {
        World w = data.world("CRM");
        jdbc.update("update companies set crm_client_id = 501, crm_client = 'ТОО «Дилер CRM»' where id = ?", w.id());
        jdbc.update("update products set crm_code = '55' where id = ?", w.product().getId());
        String issued = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusHours(2).toString();
        shipments = """
                [{"id": 1184, "clientId": 501, "issuedAt": "%s", "vehicle": "507 ACE 13", "total": 16300,
                  "lines": [{"productId": 55, "name": "Печенье", "category": "Печенье", "unit": "шт", "perBox": 10, "qty": 10, "price": 1000},
                            {"productId": 77, "name": "Торт «Медовик»", "category": "Торты", "unit": "шт", "perBox": 4, "qty": 4.0, "price": 1575}],
                  "returns": [{"id": 117, "lines": [{"productId": 55, "name": "Печенье", "qty": 6, "price": 1000}]}]}]""".formatted(issued);
        CALLS.clear();

        assertThat(sync.sync()).isEqualTo(1);
        assertThat(sync.lastError()).isNull();
        assertThat(CALLS.get(0)).startsWith("PUT /companies ").contains("\"id\":" + w.id()).contains("\"clientId\":501");
        Map<String, Object> r = jdbc.queryForMap("select id, number, status, basis, warehouse_id from receipts where crm_order_id = 1184 and company_id = ?", w.id());
        assertThat(r.get("number")).isEqualTo("CRM-1184");
        assertThat(r.get("status")).isEqualTo("DRAFT");
        assertThat(r.get("warehouse_id")).isEqualTo(w.main().getId());
        assertThat((String) r.get("basis")).contains("Заказ CRM №1184").contains("507 ACE 13").contains("возврат №117: 6 шт");
        assertThat(jdbc.queryForList("""
                select p.name || ' ' || coalesce(p.crm_code, '-') || ' ' || l.expected from receipt_items l join products p on p.id = l.product_id
                where l.receipt_id = ? order by p.crm_code""", String.class, r.get("id")))
                .containsExactly(w.product().getName() + " 55 10", "Торт «Медовик» 77 4");

        // второй обмен — тот же заказ не приходит дважды, в CRM пока сообщать нечего
        CALLS.clear();
        assertThat(sync.sync()).isZero();
        assertThat(CALLS).noneMatch(c -> c.startsWith("POST"));

        // кладовщик принял: печенья 9 из 10 — CRM узнаёт расхождение
        Long id = ((Number) r.get("id")).longValue();
        TenantContext.call(w.id(), () -> tx.execute(s -> {
            stock.confirmReceipt(id, Map.of(w.product().getId(), 9), new Actor(w.operator(), "Оператор"));
            return null;
        }));
        CALLS.clear();
        sync.sync();
        assertThat(CALLS).filteredOn(c -> c.startsWith("POST /orders/1184/received ")).singleElement().satisfies(c -> assertThat(c)
                .contains("\"productId\":55").contains("\"expected\":10,\"actual\":9").contains("\"productId\":77").contains("\"expected\":4,\"actual\":4"));
        assertThat(jdbc.queryForObject("select crm_sent_at is not null from receipts where id = ?", Boolean.class, id)).isTrue();
        CALLS.clear();
        sync.sync();
        assertThat(CALLS).noneMatch(c -> c.startsWith("POST"));
        assertThat(sync.clients()).extracting(CrmSync.CrmClient::id).containsExactly(501L);
    }

    @Test
    void пропускИзCrm_одинРазИМинуту() throws Exception {
        data.owner("Owner-pass-1");
        String ts = String.valueOf(Instant.now().getEpochSecond());
        String n = UUID.randomUUID().toString();
        MvcResult ok = mvc.perform(get("/crm-pass").param("ts", ts).param("n", n).param("who", "Бахадыр")
                        .param("sig", sign("pass|" + ts + "|" + n + "|Бахадыр")))
                .andExpect(status().is3xxRedirection()).andExpect(redirectedUrl("/admin")).andReturn();
        MockHttpSession s = (MockHttpSession) ok.getRequest().getSession(false);
        mvc.perform(get("/admin/dashboard").session(s)).andExpect(status().isOk());
        assertThat(jdbc.queryForObject("select count(*) from login_log where via = 'CRM' and who = 'Бахадыр'", Integer.class)).isEqualTo(1);

        // тот же пропуск второй раз, чужая подпись, старый пропуск — на страницу входа
        mvc.perform(get("/crm-pass").param("ts", ts).param("n", n).param("who", "Бахадыр").param("sig", sign("pass|" + ts + "|" + n + "|Бахадыр")))
                .andExpect(redirectedUrl("/login?pass"));
        String n2 = UUID.randomUUID().toString();
        mvc.perform(get("/crm-pass").param("ts", ts).param("n", n2).param("who", "Бахадыр").param("sig", sign("pass|" + ts + "|" + n2 + "|Кто-то")))
                .andExpect(redirectedUrl("/login?pass"));
        String old = String.valueOf(Instant.now().getEpochSecond() - 120);
        mvc.perform(get("/crm-pass").param("ts", old).param("n", n2).param("who", "Бахадыр").param("sig", sign("pass|" + old + "|" + n2 + "|Бахадыр")))
                .andExpect(redirectedUrl("/login?pass"));
        assertThat(jdbc.queryForObject("select count(*) from login_log where via = 'CRM'", Integer.class)).isEqualTo(1);
    }

    private static String sign(String text) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(KEY.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        return HexFormat.of().formatHex(mac.doFinal(text.getBytes(StandardCharsets.UTF_8)));
    }
}
