package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Price;
import com.confectionery.distribution.domain.PriceKind;
import com.confectionery.distribution.domain.PriceType;
import com.confectionery.distribution.domain.Product;
import com.confectionery.distribution.repository.PriceRepository;
import com.confectionery.distribution.repository.ProductRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Каталог компании и цены на сегодня. */
@Service
@RequiredArgsConstructor
public class CatalogService {

    private final ProductRepository products;
    private final PriceRepository prices;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    /** Товары компании с ценами на сегодня; companyId = null — все видимые. */
    public List<Product> products(Long companyId) {
        List<Product> list = products.findAllByOrderByNameAsc().stream()
                .filter(p -> companyId == null || companyId.equals(p.getCompanyId())).toList();
        fillPrices(list);
        return list;
    }

    /** Цены одного типа на день: id товара → цена за штуку (последняя запись с validFrom не позже дня). */
    public Map<Long, Long> pricesOn(PriceType type, LocalDate day) {
        Map<Long, Long> out = new HashMap<>();
        for (Price pr : prices.findByValidFromLessThanEqualOrderByValidFromAsc(day))
            if (pr.getPriceType().getId().equals(type.getId())) out.put(pr.getProduct().getId(), pr.getPrice());
        return out;
    }

    /** Цены на сегодня: у каждого товара и типа цен — последняя запись с validFrom не позже сегодня. */
    public void fillPrices(Collection<Product> list) {
        Map<Long, Product> byId = new HashMap<>();
        for (Product p : list) byId.put(p.getId(), p);
        for (Price pr : prices.findByValidFromLessThanEqualOrderByValidFromAsc(LocalDate.now(clock))) {
            Product p = byId.get(pr.getProduct().getId());
            if (p == null) continue;
            if (pr.getPriceType().getCode() == PriceKind.RETAIL) p.setRetail(pr.getPrice());
            else p.setWholesale(pr.getPrice());
        }
    }

    /** Цена по наценке над ценой CRM — вверх до 5 ₸: 1000 ₸ + 20 % = 1200, 1013 ₸ + 20 % = 1220. */
    public static long markupPrice(long crmPrice, int markup) {
        return (crmPrice * (100 + markup) + 499) / 500 * 5;
    }

    /**
     * Цена продажи товара с сегодня. С 04.11.2026 цена одна — пишется в оба типа цен компании (опт и розница),
     * какой бы ни был у магазина. Сегодня цену уже меняли — сегодняшняя запись переписывается; прошлые дни
     * не трогаются: заказы и возвраты тех дней считаются по своим ценам.
     */
    public void setPrice(long companyId, long productId, long price) {
        jdbc.update("""
                insert into prices (company_id, product_id, price_type_id, valid_from, price)
                select ?, ?, t.id, ?, ? from price_types t where t.company_id = ?
                on conflict (product_id, price_type_id, valid_from) do update set price = excluded.price""",
                companyId, productId, LocalDate.now(clock), price, companyId);
    }

    /** «Товары»: новые цены (id товара → цена) — только товары этой компании и только изменившиеся. Сколько изменилось. */
    @Transactional
    public int savePrices(long companyId, Map<Long, Long> changed) {
        int n = 0;
        for (Product p : products(companyId)) {
            Long price = changed.get(p.getId());
            if (price == null || price == p.getWholesale() && price == p.getRetail()) continue;
            setPrice(companyId, p.getId(), price);
            n++;
        }
        return n;
    }
}
