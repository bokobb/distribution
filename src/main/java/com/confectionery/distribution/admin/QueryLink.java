package com.confectionery.distribution.admin;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.util.UriComponentsBuilder;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Ссылки списка с фильтрами: меняется одно условие (статус, дата, страница, строк на странице), остальные
 * сохраняются. В шаблоне: {@code ${link.with('status', st)}}, {@code ${link.day('today')}}.
 */
public final class QueryLink {

    private final String path;
    private final Map<String, String[]> params;

    public QueryLink(HttpServletRequest req) {
        this.path = req.getRequestURI();
        this.params = new LinkedHashMap<>(req.getParameterMap());
    }

    /** То же, но key = value (null — убрать условие); страница — снова первая. */
    public String with(String key, Object value) {
        Map<String, String[]> p = new LinkedHashMap<>(params);
        if (!"page".equals(key)) p.remove("page");
        if (value == null) p.remove(key);
        else p.put(key, new String[]{value.toString()});
        return build(p);
    }

    /** Быстрый выбор даты: today, yesterday, all — вместо введённых «с» и «по». */
    public String day(String day) {
        Map<String, String[]> p = new LinkedHashMap<>(params);
        p.remove("from");
        p.remove("to");
        p.remove("page");
        p.put("day", new String[]{day});
        return build(p);
    }

    /** Период «с» и «по» вместо введённого. */
    public String period(Object from, Object to) {
        Map<String, String[]> p = new LinkedHashMap<>(params);
        p.remove("page");
        p.put("from", new String[]{from.toString()});
        p.put("to", new String[]{to.toString()});
        return build(p);
    }

    private String build(Map<String, String[]> p) {
        UriComponentsBuilder b = UriComponentsBuilder.fromPath(path);
        p.forEach((k, v) -> {
            if (!"_csrf".equals(k)) b.queryParam(k, (Object[]) v);
        });
        return b.encode().build().toUriString();
    }
}
