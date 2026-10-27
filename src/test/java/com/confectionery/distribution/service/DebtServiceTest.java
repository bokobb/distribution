package com.confectionery.distribution.service;

import com.confectionery.distribution.TestData;
import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.TestcontainersConfiguration;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.PaymentMethod;
import com.confectionery.distribution.service.DebtService.Balance;
import com.confectionery.distribution.service.DebtService.Debit;
import com.confectionery.distribution.tenant.TenantContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** Долг = начальный + доставлено − оплачено − возвращено; просрочка — по старым отгрузкам. */
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestData.class})
class DebtServiceTest {

    @Autowired
    TestData data;
    @Autowired
    OutletService outlets;
    @Autowired
    TransactionTemplate tx;

    static final LocalDate TODAY = LocalDate.of(2026, 10, 27);

    @Test
    void оплатыГасятСамыеСтарыеОтгрузки() {
        // 10 000 месяц назад, 5 000 вчера; оплачено 12 000 → закрыта старая и 2 000 из вчерашней
        Balance b = DebtService.balance(List.of(new Debit(TODAY.minusDays(1), 5_000), new Debit(TODAY.minusDays(30), 10_000)),
                12_000, 7, TODAY);
        assertThat(b.debt()).isEqualTo(3_000);
        assertThat(b.overdue()).isZero();
    }

    @Test
    void просроченоТоЧтоНеОплаченоИСтаршеОтсрочки() {
        Balance b = DebtService.balance(List.of(new Debit(TODAY.minusDays(10), 10_000), new Debit(TODAY.minusDays(2), 5_000)),
                3_500, 7, TODAY);
        assertThat(b.debt()).isEqualTo(11_500);
        assertThat(b.overdue()).isEqualTo(6_500);
    }

    @Test
    void срокОплатыВключительно() {
        // отгрузка 7 дней назад при отсрочке 7 — последний день, ещё не просрочено
        assertThat(DebtService.balance(List.of(new Debit(TODAY.minusDays(7), 1_000)), 0, 7, TODAY).overdue()).isZero();
        assertThat(DebtService.balance(List.of(new Debit(TODAY.minusDays(8), 1_000)), 0, 7, TODAY).overdue()).isEqualTo(1_000);
    }

    @Test
    void переплатаДаётМинус() {
        Balance b = DebtService.balance(List.of(new Debit(TODAY.minusDays(1), 1_000)), 1_500, 7, TODAY);
        assertThat(b.debt()).isEqualTo(-500);
        assertThat(b.overdue()).isZero();
    }

    @Test
    void долгМагазинаИзБазы() {
        World w = data.world("Долги");
        LocalDate today = data.today();
        data.openingDebt(w, 10_000, today.minusDays(10));
        Order o = data.order(w, today.minusDays(2), PaymentMethod.CREDIT, 5, 1_000);
        data.delivered(w, o, null, 5, today.minusDays(2).atTime(11, 0));
        Order cash = data.order(w, today, PaymentMethod.CASH, 4, 1_000);
        data.delivered(w, cash, null, 3, today.atTime(10, 0)); // частично: 3 из 4
        data.payment(w, cash, null, PaymentMethod.CASH, 3_000, today.atTime(10, 5));
        data.payment(w, null, null, PaymentMethod.KASPI, 3_000, today.atTime(10, 6)); // в счёт старого долга
        data.productReturn(w, null, 1, 500, today);

        Outlet out = TenantContext.call(w.id(), () -> tx.execute(s -> outlets.get(w.outlet().getId())));
        // 10 000 + 5 000 + 3 000 − 6 000 − 500
        assertThat(out.getDebt()).isEqualTo(11_500);
        // погашено 6 500: начальный долг (10 дней, отсрочка 7) остаётся просрочен на 3 500
        assertThat(out.getOverdue()).isEqualTo(3_500);
        assertThat(out.getLastPaymentDate()).isEqualTo(today);
        assertThat(out.getLastPaymentSum()).isEqualTo(3_000);
        assertThat(out.isOverLimit()).isFalse();
    }
}
