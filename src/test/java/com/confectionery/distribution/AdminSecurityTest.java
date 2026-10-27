package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestBuilders.formLogin;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Вход в админку и изоляция компаний на уровне страниц: сотрудник компании А по прямым адресам не
 * открывает записи компании Б, не переключает компанию и не смотрит «как владелец».
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class AdminSecurityTest {

    private static final String PASSWORD = "Проверка-2026";

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    private MockHttpSession login(String username, String password) throws Exception {
        MvcResult r = mvc.perform(formLogin("/login").user(username).password(password))
                .andExpect(redirectedUrl("/admin")).andReturn();
        return (MockHttpSession) r.getRequest().getSession(false);
    }

    private MockHttpSession login(Employee e) throws Exception {
        data.password(e, PASSWORD, false);
        return login(e.getPhone(), PASSWORD);
    }

    /** Номер так, как его набирают: «8 700 000 00 05». */
    private static String typed(String phone) {
        String d = phone.substring(2);
        return "8 " + d.substring(0, 3) + " " + d.substring(3, 6) + " " + d.substring(6, 8) + " " + d.substring(8);
    }

    @Test
    void безВходаОткрытаТолькоСтраницаВхода() throws Exception {
        mvc.perform(get("/admin/dashboard")).andExpect(status().is3xxRedirection()).andExpect(redirectedUrl("/login"));
        mvc.perform(get("/admin/outlets/1")).andExpect(status().is3xxRedirection()).andExpect(redirectedUrl("/login"));
        mvc.perform(get("/")).andExpect(status().is3xxRedirection());
        mvc.perform(get("/login")).andExpect(status().isOk()).andExpect(content().string(org.hamcrest.Matchers.containsString("Телефон или логин")));
        mvc.perform(get("/admin/assets/admin.css")).andExpect(status().isOk());
        MvcResult api = mvc.perform(get("/api/sync/pull")).andReturn();
        assertThat(api.getResponse().getStatus()).isNotEqualTo(200);
    }

    @Test
    void входПоТелефонуВЛюбомВидеИПоЛогину() throws Exception {
        World w = data.world("Вход");
        data.password(w.operator(), PASSWORD, false);
        MockHttpSession s = login(typed(w.operator().getPhone()), PASSWORD);
        mvc.perform(get("/admin/dashboard").session(s)).andExpect(status().isOk());

        mvc.perform(formLogin("/login").user(w.operator().getPhone()).password("не тот")).andExpect(redirectedUrl("/login?error"));

        String login = "oper." + w.id();
        jdbc.update("update users set login = ? where id = ?", login, w.operator().getId());
        login(login.toUpperCase(), PASSWORD);
    }

    @Test
    void агентИОтключённыйВВебНеВходят() throws Exception {
        World w = data.world("Закрыто");
        data.password(w.agent(), PASSWORD, false);
        mvc.perform(formLogin("/login").user(w.agent().getPhone()).password(PASSWORD)).andExpect(redirectedUrl("/login?error"));

        MockHttpSession s = login(w.operator());
        jdbc.update("update users set active = false where id = ?", w.operator().getId());
        // отключили, пока он работал — следующая же страница закрывает сессию
        mvc.perform(get("/admin/dashboard").session(s)).andExpect(redirectedUrl("/login?closed"));
        mvc.perform(formLogin("/login").user(w.operator().getPhone()).password(PASSWORD)).andExpect(redirectedUrl("/login?error"));
    }

    @Test
    void сотрудникКомпанииАНеОткрываетЗаписиКомпанииБ() throws Exception {
        World a = data.world("А");
        World b = data.world("Б");
        data.stockIn(b, 100);
        Order orderB = data.order(b, data.today(), PaymentMethod.CASH, 5, 500);
        Trip tripB = data.trip(b, TripStatus.ON_ROAD, orderB);

        MockHttpSession s = login(a.operator());
        mvc.perform(get("/admin/orders/" + orderB.getId()).session(s)).andExpect(status().isNotFound());
        mvc.perform(get("/admin/outlets/" + b.outlet().getId()).session(s)).andExpect(status().isNotFound());
        mvc.perform(get("/admin/trips/" + tripB.getId()).session(s)).andExpect(status().isNotFound());
        mvc.perform(get("/admin/cash/" + tripB.getId()).session(s)).andExpect(status().isNotFound());
        mvc.perform(post("/admin/outlets/" + b.outlet().getId() + "/approve").with(csrf()).session(s)).andExpect(status().isNotFound());
        mvc.perform(get("/admin/outlets").session(s)).andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.containsString(a.outlet().getName())))
                .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString(b.outlet().getName()))));

        // переключатели владельца сотруднику не помогают
        mvc.perform(get("/admin/scope").param("company", b.id().toString()).session(s));
        mvc.perform(get("/admin/as").param("role", "SUPER_ADMIN").session(s));
        mvc.perform(get("/admin/outlets/" + b.outlet().getId()).session(s)).andExpect(status().isNotFound());
        mvc.perform(get("/admin/outlets/" + a.outlet().getId()).session(s)).andExpect(status().isOk());
        mvc.perform(get("/admin/companies").session(s)).andExpect(status().is3xxRedirection());
    }

    @Test
    void разделыПоРоли() throws Exception {
        World w = data.world("Склад");
        MockHttpSession s = login(data.person(w, "Кладовщик Склада", Role.STOREKEEPER));
        mvc.perform(get("/admin/stock").session(s)).andExpect(status().isOk());
        mvc.perform(get("/admin/outlets").session(s)).andExpect(redirectedUrl("/admin/dashboard"));
        mvc.perform(get("/admin/staff").session(s)).andExpect(redirectedUrl("/admin/dashboard"));
        mvc.perform(get("/admin/settings").session(s)).andExpect(redirectedUrl("/admin/dashboard"));
    }

    @Test
    void временныйПарольСначалаСменить() throws Exception {
        World w = data.world("Пароль");
        data.password(w.operator(), PASSWORD, true);
        MockHttpSession s = login(w.operator().getPhone(), PASSWORD);
        mvc.perform(get("/admin/dashboard").session(s)).andExpect(redirectedUrl("/password"));
        mvc.perform(get("/password").session(s)).andExpect(status().isOk());

        mvc.perform(post("/password").with(csrf()).session(s).param("current", "не тот")
                        .param("password", "свой-пароль-1").param("confirm", "свой-пароль-1"))
                .andExpect(status().isOk()).andExpect(content().string(org.hamcrest.Matchers.containsString("Текущий пароль неверный")));
        mvc.perform(post("/password").with(csrf()).session(s).param("current", PASSWORD)
                        .param("password", "свой-пароль-1").param("confirm", "свой-пароль-2"))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("не совпадают")));
        mvc.perform(post("/password").with(csrf()).session(s).param("current", PASSWORD)
                        .param("password", "свой-пароль-1").param("confirm", "свой-пароль-1"))
                .andExpect(redirectedUrl("/admin"));

        mvc.perform(get("/admin/dashboard").session(s)).andExpect(status().isOk());
        assertThat(jdbc.queryForObject("select must_change_password from users where id = ?", Boolean.class, w.operator().getId())).isFalse();
        login(w.operator().getPhone(), "свой-пароль-1");
    }

    @Test
    void владелецВидитВсеКомпанииИСмотритГлазамиРоли() throws Exception {
        World a = data.world("А");
        World b = data.world("Б");
        MockHttpSession s = login(data.owner(PASSWORD), PASSWORD);
        mvc.perform(get("/admin/companies").session(s)).andExpect(status().isOk());
        mvc.perform(get("/admin/scope").param("company", "all").session(s));
        mvc.perform(get("/admin/outlets/" + b.outlet().getId()).session(s)).andExpect(status().isOk());

        mvc.perform(get("/admin/scope").param("company", a.id().toString()).session(s));
        mvc.perform(get("/admin/outlets/" + b.outlet().getId()).session(s)).andExpect(status().isNotFound());
        mvc.perform(get("/admin/outlets/" + a.outlet().getId()).session(s)).andExpect(status().isOk());

        mvc.perform(get("/admin/as").param("role", "STOREKEEPER").session(s));
        mvc.perform(get("/admin/outlets").session(s)).andExpect(redirectedUrl("/admin/dashboard"));
        mvc.perform(get("/admin/as").param("role", "SUPER_ADMIN").session(s));
        mvc.perform(get("/admin/outlets").session(s)).andExpect(status().isOk());
    }

    @Test
    void безCsrfДействиеНеПроходит_выходЗакрываетСессию() throws Exception {
        World w = data.world("Выход");
        MockHttpSession s = login(w.operator());
        mvc.perform(post("/admin/outlets/" + w.outlet().getId() + "/approve").session(s)).andExpect(status().isForbidden());
        mvc.perform(post("/admin/outlets/" + w.outlet().getId() + "/approve").with(csrf()).session(s)).andExpect(status().is3xxRedirection());

        mvc.perform(post("/logout").with(csrf()).session(s)).andExpect(redirectedUrl("/login?logout"));
        mvc.perform(get("/admin/dashboard").session(s)).andExpect(redirectedUrl("/login"));
    }
}
