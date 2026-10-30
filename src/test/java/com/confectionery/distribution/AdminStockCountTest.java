package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
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

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestBuilders.formLogin;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** «Склад» → «Ввод остатков»: на основном складе становится столько, сколько вписали; пустое поле — без изменений. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class AdminStockCountTest {

    private static final String PASSWORD = "Sklad-2026!";

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
    void вводОстатков() throws Exception {
        World w = data.world("Ввод остатков");
        data.stockIn(w, 7);
        MockHttpSession s = login(data.person(w, "Кладовщик Арман", Role.STOREKEEPER));
        String field = "qty_" + w.product().getId();

        mvc.perform(get("/admin/stock").session(s)).andExpect(content().string(containsString("/admin/stock/count")));
        mvc.perform(get("/admin/stock/count").session(s)).andExpect(status().isOk())
                .andExpect(content().string(containsString(w.product().getName())))
                .andExpect(content().string(containsString("name=\"" + field + "\"")));

        mvc.perform(post("/admin/stock/count").with(csrf()).session(s).param(field, "30")).andExpect(redirectedUrl("/admin/stock"));
        assertThat(data.balance(w.main(), w.product())).isEqualTo(30);
        mvc.perform(post("/admin/stock/count").with(csrf()).session(s).param(field, "4")).andExpect(redirectedUrl("/admin/stock"));
        assertThat(data.balance(w.main(), w.product())).isEqualTo(4);
        // пустое поле и мусор — остаток как был
        mvc.perform(post("/admin/stock/count").with(csrf()).session(s).param(field, "").param("qty_x", "5"))
                .andExpect(redirectedUrl("/admin/stock"));
        assertThat(data.balance(w.main(), w.product())).isEqualTo(4);
    }
}
