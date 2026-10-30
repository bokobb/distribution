package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Product;
import com.confectionery.distribution.domain.Receipt;
import com.confectionery.distribution.domain.ReceiptLine;
import com.confectionery.distribution.domain.ReceiptSource;
import com.confectionery.distribution.domain.ReceiptStatus;
import com.confectionery.distribution.domain.WarehouseType;
import com.confectionery.distribution.repository.CompanyRepository;
import com.confectionery.distribution.repository.ProductRepository;
import com.confectionery.distribution.repository.ReceiptRepository;
import com.confectionery.distribution.repository.WarehouseRepository;
import com.confectionery.distribution.tenant.TenantContext;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.client.RestClient;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Связь с CRM производства — только по API, базы не связаны. Раз в минуту: отправить в CRM компании и их директоров
 * (клиентов CRM), забрать выданные директорам заказы за три дня — каждый становится приходом «ждёт подтверждения»
 * на основной склад компании, — и сообщить в CRM, как подтверждённые приходы приняты (с расхождением).
 * Товар, которого у компании ещё нет, заводится по коду CRM (номер товара в CRM).
 */
@Slf4j
@Service
public class CrmSync {

    private static final DateTimeFormatter AT = DateTimeFormatter.ofPattern("dd.MM HH:mm");

    private final RestClient http;
    private final boolean enabled;
    private final CompanyRepository companies;
    private final ProductRepository products;
    private final ReceiptRepository receipts;
    private final WarehouseRepository warehouses;
    private final SettingsService settings;
    private final JdbcTemplate jdbc;
    private final TransactionTemplate tx;
    private final Clock clock;

    private volatile LocalDateTime lastOk;
    private volatile String lastError;

    public CrmSync(@Value("${distribution.crm.url:}") String url, @Value("${distribution.crm.key:}") String key,
                   CompanyRepository companies, ProductRepository products, ReceiptRepository receipts,
                   WarehouseRepository warehouses, SettingsService settings, JdbcTemplate jdbc, TransactionTemplate tx,
                   Clock clock) {
        this.enabled = url != null && !url.isBlank() && key != null && !key.isBlank();
        SimpleClientHttpRequestFactory rf = new SimpleClientHttpRequestFactory();
        rf.setConnectTimeout(Duration.ofSeconds(5));
        rf.setReadTimeout(Duration.ofSeconds(20));
        this.http = RestClient.builder().requestFactory(rf)
                .baseUrl(enabled ? url.replaceAll("/+$", "") + "/api/distribution" : "http://localhost")
                .defaultHeader("X-Dist-Key", enabled ? key.trim() : "")
                .build();
        this.companies = companies;
        this.products = products;
        this.receipts = receipts;
        this.warehouses = warehouses;
        this.settings = settings;
        this.jdbc = jdbc;
        this.tx = tx;
        this.clock = clock;
    }

    public record CrmClient(Long id, String name, String phone) {
    }

    record CompanyOut(Long id, String name, Long clientId) {
    }

    record Line(Long productId, String name, String category, String unit, BigDecimal perBox, BigDecimal qty, BigDecimal price) {
    }

    record Return(Long id, List<Line> lines) {
    }

    record Shipment(Long id, Long clientId, LocalDateTime issuedAt, String vehicle, BigDecimal total, List<Line> lines,
                    List<Return> returns) {
    }

    record ReceivedLine(Long productId, String name, int expected, int actual) {
    }

    record Received(String company, String by, LocalDateTime at, List<ReceivedLine> lines) {
    }

    public boolean enabled() {
        return enabled;
    }

    /** Последний удачный обмен; null — ещё не было. */
    public LocalDateTime lastOk() {
        return lastOk;
    }

    public String lastError() {
        return lastError;
    }

    /** Клиенты CRM для выбора директора компании; связи нет или CRM не ответила — пусто. */
    public List<CrmClient> clients() {
        if (!enabled) return List.of();
        try {
            CrmClient[] list = http.get().uri(u -> u.path("/clients").queryParam("limit", 1000).build())
                    .retrieve().body(CrmClient[].class);
            return list == null ? List.of() : List.of(list);
        } catch (RuntimeException e) {
            log.warn("CRM: список клиентов не получен: {}", e.getMessage());
            return List.of();
        }
    }

    @Scheduled(initialDelayString = "${distribution.crm.sync-delay-ms:20000}", fixedDelayString = "${distribution.crm.sync-ms:60000}")
    public void scheduled() {
        if (enabled) sync();
    }

    /** Обмен с CRM целиком; ошибка не мешает следующему разу. Возвращает, сколько новых приходов создано. */
    public int sync() {
        try {
            List<Company> linked = TenantContext.asRoot(() -> tx.execute(s -> companies.findAllByOrderByIdAsc().stream()
                    .filter(c -> c.isActive() && c.getCrmClientId() != null).toList()));
            http.put().uri("/companies")
                    .body(linked.stream().map(c -> new CompanyOut(c.getId(), c.getName(), c.getCrmClientId())).toList())
                    .retrieve().toBodilessEntity();
            int created = 0;
            if (!linked.isEmpty()) {
                LocalDateTime since = LocalDateTime.now(clock).minusDays(3).withNano(0);
                String ids = linked.stream().map(c -> String.valueOf(c.getCrmClientId())).collect(Collectors.joining(","));
                Shipment[] list = http.get().uri(u -> u.path("/shipments").queryParam("since", since).queryParam("clients", ids).build())
                        .retrieve().body(Shipment[].class);
                Map<Long, Company> byClient = new HashMap<>();
                linked.forEach(c -> byClient.put(c.getCrmClientId(), c));
                for (Shipment sh : list == null ? new Shipment[0] : list) {
                    Company c = byClient.get(sh.clientId());
                    if (c != null && Boolean.TRUE.equals(TenantContext.asRoot(() -> tx.execute(s -> receive(c, sh))))) created++;
                }
            }
            report();
            lastOk = LocalDateTime.now(clock);
            lastError = null;
            return created;
        } catch (RuntimeException e) {
            lastError = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            log.warn("CRM: обмен не удался: {}", lastError);
            return 0;
        }
    }

    /** Выданный заказ CRM — приход «ждёт подтверждения» на основной склад; уже есть — ничего. */
    private boolean receive(Company c, Shipment sh) {
        if (!settings.of(c.getId()).isAutoReceipt()) return false;
        Integer had = jdbc.queryForObject("select count(*) from receipts where company_id = ? and crm_order_id = ?",
                Integer.class, c.getId(), sh.id());
        if (had != null && had > 0) return false;
        Receipt r = new Receipt().setNumber("CRM-" + sh.id()).setSource(ReceiptSource.CRM).setStatus(ReceiptStatus.DRAFT)
                .setDate(sh.issuedAt().toLocalDate()).setSupplier("Производство (CRM)")
                .setBasis(basis(sh)).setWarehouse(warehouses.findByCompanyIdAndType(c.getId(), WarehouseType.MAIN).orElseThrow())
                .setCreatedAt(LocalDateTime.now(clock)).setCrmOrderId(sh.id());
        r.setCompany(c);
        Map<Long, Integer> qty = new java.util.LinkedHashMap<>();
        Map<Long, Line> first = new HashMap<>();
        for (Line l : sh.lines()) {
            qty.merge(l.productId(), l.qty().setScale(0, RoundingMode.HALF_UP).intValue(), Integer::sum);
            first.putIfAbsent(l.productId(), l);
        }
        Map<Long, BigDecimal> price = new HashMap<>();
        for (Map.Entry<Long, Integer> e : qty.entrySet()) {
            if (e.getValue() <= 0) continue;
            Product p = product(c, first.get(e.getKey()));
            r.addLine(new ReceiptLine().setProduct(p).setExpected(e.getValue()));
            if (first.get(e.getKey()).price() != null) price.put(p.getId(), first.get(e.getKey()).price());
        }
        if (r.getLines().isEmpty()) return false;
        receipts.save(r);
        // цена CRM — для наценки в «Товарах»; более старый заказ свежую цену не затирает
        price.forEach((id, pr) -> jdbc.update("""
                update products set crm_price = ?, crm_price_at = ? where id = ? and (crm_price_at is null or crm_price_at <= ?)""",
                pr.setScale(0, RoundingMode.HALF_UP).longValue(), sh.issuedAt(), id, sh.issuedAt()));
        return true;
    }

    /** «Заказ CRM №1184, выдан 28.10 08:35, 507 ACE 13 · возврат №117: 6 шт». */
    private static String basis(Shipment sh) {
        StringBuilder b = new StringBuilder("Заказ CRM №" + sh.id() + ", выдан " + sh.issuedAt().format(AT));
        if (sh.vehicle() != null && !sh.vehicle().isBlank()) b.append(", ").append(sh.vehicle().strip());
        for (Return r : sh.returns() == null ? List.<Return>of() : sh.returns()) {
            int n = r.lines().stream().mapToInt(l -> l.qty().setScale(0, RoundingMode.HALF_UP).intValue()).sum();
            b.append(" · возврат №").append(r.id()).append(": ").append(n).append(" шт");
        }
        return b.length() > 300 ? b.substring(0, 300) : b.toString();
    }

    /** Товар компании с кодом CRM; нет — заводится из CRM: название, категория, штук в коробке. */
    private Product product(Company c, Line l) {
        String code = String.valueOf(l.productId());
        List<Long> ids = jdbc.queryForList("select id from products where company_id = ? and crm_code = ?", Long.class, c.getId(), code);
        if (!ids.isEmpty()) return products.getReferenceById(ids.get(0));
        Product p = new Product().setName(cut(l.name(), 200)).setCategory(l.category() == null || l.category().isBlank() ? "Из CRM" : cut(l.category(), 100))
                .setUnit(l.unit() == null || l.unit().isBlank() ? "шт" : cut(l.unit(), 16))
                .setPerBox(l.perBox() == null || l.perBox().signum() <= 0 ? 1 : Math.max(1, l.perBox().intValue()))
                .setCrmCode(code);
        p.setCompany(c);
        return products.save(p);
    }

    /** Подтверждённые приходы из CRM, о которых CRM ещё не знает: сколько принято по каждой строке. */
    private void report() {
        List<Long> ids = jdbc.queryForList("""
                select id from receipts where crm_order_id is not null and status = 'CONFIRMED' and crm_sent_at is null
                order by id limit 50""", Long.class);
        for (Long id : ids) {
            Received body = TenantContext.asRoot(() -> tx.execute(s -> {
                Receipt r = receipts.findById(id).orElseThrow();
                List<ReceivedLine> lines = new ArrayList<>();
                for (ReceiptLine l : r.getLines())
                    lines.add(new ReceivedLine(crmId(l.getProduct()), l.getProduct().getName(), l.getExpected(),
                            l.getActual() == null ? l.getExpected() : l.getActual()));
                return new Received(r.getCompany().getName(), r.getConfirmedBy(), r.getConfirmedAt(), lines);
            }));
            Long order = jdbc.queryForObject("select crm_order_id from receipts where id = ?", Long.class, id);
            http.post().uri("/orders/{id}/received", order).body(body).retrieve().toBodilessEntity();
            jdbc.update("update receipts set crm_sent_at = ? where id = ?", LocalDateTime.now(clock), id);
        }
    }

    private static Long crmId(Product p) {
        try {
            return p.getCrmCode() == null ? null : Long.valueOf(p.getCrmCode());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static String cut(String s, int max) {
        return s.length() > max ? s.substring(0, max) : s;
    }
}
