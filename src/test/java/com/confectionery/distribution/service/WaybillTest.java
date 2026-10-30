package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** Общая накладная: отгружено по группам, чистый возврат — невыданное, испорченный — негодный от магазинов. */
class WaybillTest {

    private static Product product(String name, String group, int perBox) {
        return new Product().setName(name).setCategory(group).setPerBox(perBox);
    }

    private static Order order(OrderStatus status, Product p, int qty, long price) {
        Order o = new Order().setStatus(status).setOutlet(new Outlet());
        o.addLine(new OrderLine().setProduct(p).setQty(qty).setPrice(price));
        return o;
    }

    private static void deliver(Order o, DeliveryStatus status, Product p, int qty) {
        Delivery d = new Delivery().setOrder(o).setStatus(status);
        if (qty > 0) d.getItems().add(new DeliveryItem().setDelivery(d).setProduct(p).setQty(qty));
        o.getDeliveries().add(d);
    }

    @Test
    void отгруженоПоГруппамЧистыйИИспорченныйВозврат() {
        Product bun = product("Булочки (12 шт)", "Булочки", 12);
        Product cake = product("Кекс (15 шт)", "Кексы", 15);
        Product cookie = product("Коржики (12 шт)", "Коржики", 12);

        Order full = order(OrderStatus.DELIVERED, bun, 30, 400);     // выдано всё
        deliver(full, DeliveryStatus.DELIVERED, bun, 30);
        Order part = order(OrderStatus.PARTIAL, cake, 20, 500);       // взяли 15 из 20
        deliver(part, DeliveryStatus.PARTIAL, cake, 15);
        Order closed = order(OrderStatus.REFUSED, bun, 6, 400);       // магазин закрыт
        deliver(closed, DeliveryStatus.REFUSED, bun, 0);
        Order planned = order(OrderStatus.IN_TRIP, cookie, 12, 420);  // ещё не выдан, торговый записал возврат
        planned.addReturnLine(new OrderReturnLine().setProduct(cookie).setQty(3).setPrice(420));

        OrderService.Waybill w = OrderService.waybill(List.of(full, part, closed, planned));

        assertThat(w.shipped().groups()).extracting(OrderService.SumGroup::name).containsExactly("Булочки", "Кексы", "Коржики");
        OrderService.SumGroup buns = w.shipped().groups().get(0);
        assertThat(buns.qty()).isEqualTo(36);
        assertThat(buns.rows().get(0).boxes()).isEqualTo(3);
        assertThat(w.shipped().sum()).isEqualTo(36 * 400 + 20 * 500 + 12 * 420);

        // чистый: 6 булочек закрытого магазина и 5 кексов, которые не взяли
        assertThat(w.clean().qty()).isEqualTo(11);
        assertThat(w.clean().sum()).isEqualTo(6 * 400 + 5 * 500);
        // испорченный: пока не выдан — записанное торговым
        assertThat(w.spoiled().qty()).isEqualTo(3);
        assertThat(w.planned()).isEqualTo(3);
    }

    @Test
    void пустыеРазделы() {
        Product bun = product("Булочки", null, 1);
        OrderService.Waybill w = OrderService.waybill(List.of(order(OrderStatus.IN_TRIP, bun, 5, 100)));
        assertThat(w.shipped().groups()).extracting(OrderService.SumGroup::name).containsExactly("Без группы");
        assertThat(w.clean().isEmpty()).isTrue();
        assertThat(w.spoiled().isEmpty()).isTrue();
    }
}
