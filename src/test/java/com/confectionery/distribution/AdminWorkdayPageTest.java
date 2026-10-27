package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.AppEventKind;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.time.LocalDateTime;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestBuilders.formLogin;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Страница «Рабочий день»: день и пропажи GPS видны оператору, период не длиннее 31 дня, кладовщику отчёт закрыт. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class AdminWorkdayPageTest {

    private static final String PASSWORD = "Проверка-2026";

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;

    private MockHttpSession login(Employee e) throws Exception {
        data.password(e, PASSWORD, false);
        MvcResult r = mvc.perform(formLogin("/login").user(e.getPhone()).password(PASSWORD)).andExpect(redirectedUrl("/admin")).andReturn();
        return (MockHttpSession) r.getRequest().getSession(false);
    }

    @Test
    void рабочийДеньСтраницей() throws Exception {
        World w = data.world("Рабочий день страницей");
        World other = data.world("Чужой день страницей");
        LocalDateTime day = data.today().minusDays(1).atStartOfDay();
        data.event(w.agent(), day.plusHours(9), AppEventKind.DAY_START);
        data.point(w.agent(), day.plusHours(9).plusMinutes(5), 42.3, 69.58);
        data.event(w.agent(), day.plusHours(10), AppEventKind.GPS_OFF);
        data.event(w.agent(), day.plusHours(11), AppEventKind.DAY_END);
        data.event(other.agent(), day.plusHours(9), AppEventKind.DAY_START);
        MockHttpSession s = login(w.operator());
        String date = day.toLocalDate().toString();

        mvc.perform(get("/admin/reports").session(s)).andExpect(content().string(containsString("/admin/reports/workday")));
        mvc.perform(get("/admin/reports/workday").session(s).param("from", date).param("to", date))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString(w.agent().getName())))
                .andExpect(content().string(containsString("09:05–11:00 · GPS выключен")))
                .andExpect(content().string(containsString("Закончил день")))
                .andExpect(content().string(not(containsString(other.agent().getName()))));

        mvc.perform(get("/admin/reports/workday").session(s).param("from", data.today().minusDays(90).toString()).param("to", date))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("показаны последние 31")));

        Employee storekeeper = data.person(w, "Кладовщик дня", Role.STOREKEEPER);
        mvc.perform(get("/admin/reports/workday").session(login(storekeeper))).andExpect(redirectedUrl("/admin/dashboard"));
    }
}
