package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Price;
import com.confectionery.distribution.domain.PriceKind;
import com.confectionery.distribution.domain.PriceType;
import com.confectionery.distribution.domain.Product;
import com.confectionery.distribution.repository.PriceRepository;
import com.confectionery.distribution.repository.ProductRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

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
}
