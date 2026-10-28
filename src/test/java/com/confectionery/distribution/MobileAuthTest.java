package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.service.StaffService;
import com.confectionery.distribution.tenant.TenantContext;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Вход приложения агента и экспедитора: пароль один раз — JWT и ключ устройства; дальше новый JWT по ключу.
 * Отключение, сброс пароля и «Выйти» закрывают вход; временный пароль сначала меняется.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class MobileAuthTest {

    private static final String PASSWORD = "Проверка-2026";

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;
    @Autowired
    StaffService staff;

    private record Tokens(String jwt, String device) {
    }

    private ResultActions postJson(String url, String json) throws Exception {
        return mvc.perform(post(url).contentType(MediaType.APPLICATION_JSON).content(json));
    }

    private ResultActions login(String login, String password) throws Exception {
        return postJson("/api/mobile/auth/login", """
                {"login": "%s", "password": "%s", "device": "Samsung SM-A515F", "appVersion": "1.0.0+1"}""".formatted(login, password));
    }

    private Tokens loginOk(Employee e) throws Exception {
        String body = login(e.getPhone(), PASSWORD).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return new Tokens(JsonPath.read(body, "$.token"), JsonPath.read(body, "$.deviceToken"));
    }

    private ResultActions me(String jwt) throws Exception {
        return mvc.perform(get("/api/mobile/me").header("Authorization", "Bearer " + jwt));
    }

    private ResultActions refresh(String device) throws Exception {
        return postJson("/api/mobile/auth/refresh", "{\"deviceToken\": \"" + device + "\"}");
    }

    private int keys(Employee e) {
        return jdbc.queryForObject("select count(*) from device_sessions where user_id = ?", Integer.class, e.getId());
    }

    @Test
    void агентВходитПоТелефонуВЛюбомВиде() throws Exception {
        World w = data.world("Приложение");
        data.password(w.agent(), PASSWORD, false);
        String d = w.agent().getPhone().substring(2);
        String typed = "8 (" + d.substring(0, 3) + ") " + d.substring(3, 6) + "-" + d.substring(6, 8) + "-" + d.substring(8);

        String body = login(typed, PASSWORD).andExpect(status().isOk())
                .andExpect(jsonPath("$.expiresIn").value(720 * 60))
                .andExpect(jsonPath("$.user.id").value(w.agent().getId()))
                .andExpect(jsonPath("$.user.role").value("AGENT"))
                .andExpect(jsonPath("$.user.company").value(w.company().getName()))
                .andExpect(jsonPath("$.user.mustChangePassword").value(false))
                .andReturn().getResponse().getContentAsString();

        me(JsonPath.read(body, "$.token")).andExpect(status().isOk()).andExpect(jsonPath("$.name").value(w.agent().getName()));
        // в базе только хеш ключа; вход записан в журнал приложения с моделью телефона
        String device = JsonPath.read(body, "$.deviceToken");
        assertThat(jdbc.queryForObject("select token_hash from device_sessions where user_id = ?", String.class, w.agent().getId()))
                .hasSize(64).isNotEqualTo(device);
        assertThat(jdbc.queryForObject("select device from app_events where user_id = ? and kind = 'LOGIN'", String.class, w.agent().getId()))
                .isEqualTo("Samsung SM-A515F");
    }

    @Test
    void неверныйПароль_веб_роли_иОтключённыйНеВходят() throws Exception {
        World w = data.world("Не входят");
        data.password(w.agent(), PASSWORD, false);
        data.password(w.operator(), PASSWORD, false);

        login(w.agent().getPhone(), "не тот").andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.message").value("Неверный телефон или пароль"));
        login("+7 799 999 99 99", PASSWORD).andExpect(status().isUnauthorized());
        login(w.operator().getPhone(), PASSWORD).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message", containsString("веб-админке")));

        jdbc.update("update users set active = false where id = ?", w.agent().getId());
        login(w.agent().getPhone(), PASSWORD).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Вход закрыт — обратитесь к директору"));
        assertThat(keys(w.agent())).isZero();
    }

    @Test
    void безJwtИСПоддельным_401() throws Exception {
        mvc.perform(get("/api/mobile/me")).andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.message").value("Войдите заново"));
        me("abc.def.ghi").andExpect(status().isUnauthorized());
        // прочий /api по-прежнему закрыт
        assertThat(mvc.perform(get("/api/sync/pull")).andReturn().getResponse().getStatus()).isNotEqualTo(200);
    }

    @Test
    void ключУстройстваДаётНовыйJwt_выходЗакрываетКлюч() throws Exception {
        World w = data.world("Ключ");
        data.password(w.expeditor(), PASSWORD, false);
        Tokens t = loginOk(w.expeditor());

        String body = refresh(t.device()).andExpect(status().isOk())
                .andExpect(jsonPath("$.deviceToken").value(t.device()))
                .andExpect(jsonPath("$.user.role").value("EXPEDITOR"))
                .andReturn().getResponse().getContentAsString();
        me(JsonPath.read(body, "$.token")).andExpect(status().isOk());

        postJson("/api/mobile/auth/logout", "{\"deviceToken\": \"" + t.device() + "\"}").andExpect(status().isNoContent());
        refresh(t.device()).andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.message", containsString("войдите с паролем")));
        refresh("выдуманный").andExpect(status().isUnauthorized());
        assertThat(jdbc.queryForObject("select count(*) from app_events where user_id = ? and kind = 'LOGOUT'", Integer.class,
                w.expeditor().getId())).isEqualTo(1);
    }

    @Test
    void отключилиСотрудника_доступПропадаетСразу() throws Exception {
        World w = data.world("Отключили");
        data.password(w.agent(), PASSWORD, false);
        Tokens t = loginOk(w.agent());

        TenantContext.run(TenantContext.ROOT, () -> staff.setActive(w.agent().getId(), false, null));

        me(t.jwt()).andExpect(status().isUnauthorized());
        refresh(t.device()).andExpect(status().isUnauthorized());
        assertThat(keys(w.agent())).isZero();
    }

    @Test
    void сбросПароляЗакрываетВходНаТелефонах() throws Exception {
        World w = data.world("Сброс");
        data.password(w.agent(), PASSWORD, false);
        Tokens t = loginOk(w.agent());

        TenantContext.run(TenantContext.ROOT, () -> staff.resetPassword(w.agent().getId()));

        refresh(t.device()).andExpect(status().isUnauthorized());
        // JWT ещё не истёк, но пароль временный — открыта только его смена
        me(t.jwt()).andExpect(status().isForbidden()).andExpect(jsonPath("$.message").value("Сначала смените временный пароль"));
    }

    @Test
    void временныйПарольСначалаСменить_остальныеТелефоныВыходят() throws Exception {
        World w = data.world("Временный");
        data.password(w.agent(), PASSWORD, true);
        String first = login(w.agent().getPhone(), PASSWORD).andExpect(jsonPath("$.user.mustChangePassword").value(true))
                .andReturn().getResponse().getContentAsString();
        Tokens a = new Tokens(JsonPath.read(first, "$.token"), JsonPath.read(first, "$.deviceToken"));
        Tokens b = loginOk(w.agent());

        me(a.jwt()).andExpect(status().isForbidden());
        String wrong = """
                {"current": "не тот", "password": "свой-пароль-1", "confirm": "свой-пароль-1", "deviceToken": "%s"}""".formatted(a.device());
        mvc.perform(post("/api/mobile/auth/password").header("Authorization", "Bearer " + a.jwt())
                        .contentType(MediaType.APPLICATION_JSON).content(wrong))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value("Текущий пароль неверный"));
        String good = """
                {"current": "%s", "password": "свой-пароль-1", "confirm": "свой-пароль-1", "deviceToken": "%s"}""".formatted(PASSWORD, a.device());
        mvc.perform(post("/api/mobile/auth/password").header("Authorization", "Bearer " + a.jwt())
                        .contentType(MediaType.APPLICATION_JSON).content(good))
                .andExpect(status().isOk()).andExpect(jsonPath("$.mustChangePassword").value(false));

        me(a.jwt()).andExpect(status().isOk());
        refresh(a.device()).andExpect(status().isOk());
        refresh(b.device()).andExpect(status().isUnauthorized());
        login(w.agent().getPhone(), "свой-пароль-1").andExpect(status().isOk());
    }

    @Test
    void подборПароля_паузаПослеПятиОшибок() throws Exception {
        World w = data.world("Подбор");
        data.password(w.agent(), PASSWORD, false);
        for (int i = 0; i < 5; i++) login(w.agent().getPhone(), "не тот " + i).andExpect(status().isUnauthorized());

        login(w.agent().getPhone(), PASSWORD).andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.message", containsString("подождите")));
    }
}
