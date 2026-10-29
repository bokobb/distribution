package com.confectionery.distribution.service;

import com.confectionery.distribution.TestData;
import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.TestcontainersConfiguration;
import com.confectionery.distribution.domain.AppEventKind;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.VisitResult;
import com.confectionery.distribution.tenant.TenantContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** «Рабочий день»: начало и конец, часы, км, пропажи GPS с причиной, старая версия приложения, журнал своей компании. */
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestData.class})
class WorkdayReportTest {

    @Autowired
    TestData data;
    @Autowired
    WorkdayReport report;
    @Autowired
    TransactionTemplate tx;

    World w;
    LocalDate date;
    LocalDateTime day;

    @BeforeEach
    void setUp() {
        w = data.world("Рабочий день");
        date = data.today().minusDays(1);
        day = date.atStartOfDay();
        Employee agent = w.agent();
        data.event(agent, day.plusHours(8).plusMinutes(30), AppEventKind.DAY_START, "1.0.1");
        data.event(agent, day.plusHours(12), AppEventKind.GPS_OFF, "1.0.1");
        data.event(agent, day.plusHours(12).plusMinutes(40), AppEventKind.GPS_ON, "1.0.1");
        data.event(agent, day.plusHours(17), AppEventKind.DAY_END, "1.0.1");
        for (LocalDateTime t = day.plusHours(8).plusMinutes(35); t.isBefore(day.plusHours(17)); t = t.plusMinutes(5))
            if (t.isBefore(day.plusHours(11).plusMinutes(56)) || t.isAfter(day.plusHours(12).plusMinutes(44)))
                data.point(agent, t, 42.30 + (t.getHour() - 8) * 0.002, 69.58);
        data.visit(w, w.outlet(), day.plusHours(10), VisitResult.ORDER, null, null);

        // экспедитор начал день и не закрыл, одна точка
        data.event(w.expeditor(), day.plusHours(8).plusMinutes(30), AppEventKind.DAY_START, "0.9.8");
        data.point(w.expeditor(), day.plusHours(9), 42.30, 69.58);

        World other = data.world("Чужой рабочий день");
        data.event(other.agent(), day.plusHours(9), AppEventKind.DAY_START, "1.0.0");
    }

    private WorkdayReport.Report build(List<Long> who) {
        return TenantContext.call(w.id(), () -> tx.execute(s -> report.build(null, date, date, who)));
    }

    @Test
    void деньТорговогоИЭкспедитора() {
        WorkdayReport.Report r = build(List.of());
        assertThat(r.rows()).extracting(WorkdayReport.Row::name).containsExactly(w.agent().getName(), w.expeditor().getName());

        WorkdayReport.Row agent = r.rows().get(0);
        assertThat(agent.start()).isEqualTo(day.plusHours(8).plusMinutes(30));
        assertThat(agent.end()).isEqualTo(day.plusHours(17));
        assertThat(agent.hours()).isEqualTo("8 ч 30 мин");
        assertThat(agent.gpsOn()).isTrue();
        assertThat(agent.km()).isGreaterThan(1);
        assertThat(agent.work()).isEqualTo("визитов 1 · с заказом 1");
        assertThat(agent.gaps()).singleElement().satisfies(g -> {
            assertThat(g.from()).isEqualTo("11:55");
            assertThat(g.to()).isEqualTo("12:45");
            assertThat(g.cause()).isEqualTo("GPS выключен");
        });
        assertThat(agent.oldApp()).isFalse();

        WorkdayReport.Row exp = r.rows().get(1);
        assertThat(exp.open()).isTrue();
        assertThat(exp.end()).isNull();
        // не закрыл вчера — считается до последнего, что прислал телефон
        assertThat(exp.hours()).isEqualTo("0 ч 30 мин");
        assertThat(exp.work()).isEqualTo("выдач нет");
        assertThat(exp.app()).isEqualTo("0.9.8");
        assertThat(exp.oldApp()).isTrue();
        assertThat(r.latestApp()).isEqualTo("1.0.1");
    }

    @Test
    void журналСначалаНовыеИТолькоВыбранные() {
        WorkdayReport.Report r = build(List.of(w.agent().getId()));
        assertThat(r.rows()).extracting(WorkdayReport.Row::name).containsExactly(w.agent().getName());
        assertThat(r.journal()).extracting(WorkdayReport.Entry::kind)
                .containsExactly(AppEventKind.DAY_END, AppEventKind.GPS_ON, AppEventKind.GPS_OFF, AppEventKind.DAY_START);
    }

    @Test
    void версииСравниваютсяПоЧислам() {
        assertThat(WorkdayReport.compareVersions("1.0.10", "1.0.9")).isPositive();
        assertThat(WorkdayReport.compareVersions("1.2", "1.2.0")).isZero();
    }
}
