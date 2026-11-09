package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.service.CatalogService;
import com.confectionery.distribution.service.PriceListXlsx;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestBuilders.formLogin;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * «Товары» с 04.11.2026: одна цена продажи (пишется и в опт, и в розницу) рядом с ценой CRM и наценкой;
 * меняют директор и владелец, оператор только смотрит; новая цена — с сегодня, прошлые дни не трогаются.
 * С 09.11.2026 «Скачать прайс» — Excel для магазинов.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class ProductPricesTest {

    private static final String PASSWORD = "Ceny-2026!";

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    private MockHttpSession login(Employee e) throws Exception {
        data.password(e, PASSWORD, false);
        MvcResult r = mvc.perform(formLogin("/login").user(e.getPhone()).password(PASSWORD)).andExpect(redirectedUrl("/admin")).andReturn();
        return (MockHttpSession) r.getRequest().getSession(false);
    }

    /** «КОД цена» по обоим типам цен товара на дату. */
    private java.util.List<String> prices(World w, LocalDate day) {
        return jdbc.queryForList("""
                select t.code || ' ' || p.price from prices p join price_types t on t.id = p.price_type_id
                where p.product_id = ? and p.valid_from = ? order by t.code""", String.class, w.product().getId(), day);
    }

    @Test
    void ценаПоНаценке_вверхДо5Тенге() {
        assertThat(CatalogService.markupPrice(1000, 20)).isEqualTo(1200);
        assertThat(CatalogService.markupPrice(1013, 20)).isEqualTo(1220);
        assertThat(CatalogService.markupPrice(1575, 20)).isEqualTo(1890);
        assertThat(CatalogService.markupPrice(999, 0)).isEqualTo(1000);
    }

    @Test
    void директорМеняетЦенуИНаценку() throws Exception {
        World w = data.world("Цены");
        World other = data.world("Чужие цены");
        jdbc.update("update products set crm_price = 1000 where id = ?", w.product().getId());
        LocalDate yesterday = data.today().minusDays(1);
        jdbc.update("""
                insert into prices (company_id, product_id, price_type_id, valid_from, price)
                select ?, ?, id, ?, 1100 from price_types where company_id = ?""", w.id(), w.product().getId(), yesterday, w.id());
        MockHttpSession s = login(data.person(w, "Директор Ерлан", Role.DIRECTOR));
        String field = "price_" + w.product().getId();

        mvc.perform(get("/admin/products").session(s)).andExpect(status().isOk())
                .andExpect(content().string(containsString("name=\"" + field + "\"")))
                .andExpect(content().string(containsString("Поставить всем")))
                .andExpect(content().string(not(containsString(">Опт<"))));

        mvc.perform(post("/admin/products/prices").with(csrf()).session(s).param("markup", "25").param(field, "1 300")
                        .param("price_" + other.product().getId(), "5"))
                .andExpect(redirectedUrl("/admin/products"));
        assertThat(prices(w, data.today())).containsExactly("RETAIL 1300", "WHOLESALE 1300");
        assertThat(prices(w, yesterday)).containsExactly("RETAIL 1100", "WHOLESALE 1100");
        assertThat(jdbc.queryForObject("select price_markup from company_settings where company_id = ?", Integer.class, w.id())).isEqualTo(25);
        // чужой товар в форме не меняется
        assertThat(jdbc.queryForObject("select count(*) from prices where product_id = ?", Integer.class, other.product().getId())).isZero();

        // второй раз за день — сегодняшняя запись переписывается, не дублируется
        mvc.perform(post("/admin/products/prices").with(csrf()).session(s).param("markup", "25").param(field, "1250"))
                .andExpect(redirectedUrl("/admin/products"));
        assertThat(prices(w, data.today())).containsExactly("RETAIL 1250", "WHOLESALE 1250");

        // неверная цена — ничего не сохраняется
        mvc.perform(post("/admin/products/prices").with(csrf()).session(s).param("markup", "30").param(field, "0"))
                .andExpect(redirectedUrl("/admin/products"));
        assertThat(prices(w, data.today())).containsExactly("RETAIL 1250", "WHOLESALE 1250");
        assertThat(jdbc.queryForObject("select price_markup from company_settings where company_id = ?", Integer.class, w.id())).isEqualTo(25);

        mvc.perform(get("/admin/products").session(s)).andExpect(content().string(containsString("value=\"1250\"")))
                .andExpect(content().string(containsString("value=\"25\"")));
    }

    @Test
    void операторТолькоСмотрит() throws Exception {
        World w = data.world("Цены оператор");
        MockHttpSession s = login(w.operator());
        mvc.perform(get("/admin/products").session(s)).andExpect(status().isOk())
                .andExpect(content().string(containsString("нет цены")))
                .andExpect(content().string(not(containsString("name=\"price_"))))
                .andExpect(content().string(not(containsString("Поставить всем"))));
        mvc.perform(post("/admin/products/prices").with(csrf()).session(s).param("markup", "20").param("price_" + w.product().getId(), "999"))
                .andExpect(status().isForbidden());
        assertThat(prices(w, data.today())).isEmpty();
    }

    @Test
    void прайсВExcel_ценаCrm_ценаПродажи_наценка() throws Exception {
        World w = data.world("Прайс");
        jdbc.update("update products set crm_price = 777 where id = ?", w.product().getId());
        jdbc.update("""
                insert into prices (company_id, product_id, price_type_id, valid_from, price)
                select ?, ?, id, ?, 1250 from price_types where company_id = ?""", w.id(), w.product().getId(), data.today(), w.id());
        // без цены — пустая ячейка, выключенный — не идёт
        jdbc.update("""
                insert into products (company_id, name, category, unit, per_box, active)
                values (?, 'Вафли без цены', 'Вафли', 'шт', 6, true), (?, 'Старый торт', 'Торты', 'шт', 1, false)""", w.id(), w.id());
        MockHttpSession s = login(data.person(w, "Директор Прайс", Role.DIRECTOR));

        mvc.perform(get("/admin/products").session(s)).andExpect(content().string(containsString("Скачать прайс")));
        MvcResult r = mvc.perform(get("/admin/products/price.xlsx").session(s)).andExpect(status().isOk())
                .andExpect(header().string("Content-Disposition", containsString("attachment")))
                .andExpect(header().string("Content-Disposition", containsString(".xlsx")))
                .andReturn();
        assertThat(r.getResponse().getContentType()).startsWith("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        List<List<String>> rows = PriceListXlsxTest.sheet(r.getResponse().getContentAsByteArray());
        String all = rows.toString();
        assertThat(rows.get(0).get(0)).isEqualTo("Прайс — " + w.company().getName());
        assertThat(rows.get(1)).containsExactly("Цены на " + PriceListXlsx.DAY.format(data.today()));
        assertThat(rows).contains(List.of("Печенье", "", "", ""));
        assertThat(rows).contains(List.of(w.product().getName(), "777", "1 250", "61%"));
        assertThat(rows).contains(List.of("Вафли без цены", "", "", ""));
        assertThat(all).doesNotContain("Старый торт");

        // оператор не меняет цены, но прайс скачивает
        MockHttpSession op = login(w.operator());
        mvc.perform(get("/admin/products/price.xlsx").session(op)).andExpect(status().isOk());
    }
}
