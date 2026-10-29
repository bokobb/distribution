package com.confectionery.distribution.admin;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

/**
 * Значки админки — SVG 24×24 (admin/icons.json: имя → содержимое svg), как в CRM. В шаблонах —
 * картой из модели: th:utext="${i['orders']}" (20 px) и ${i16['check']} (16 px).
 */
@Component
public class AdminIcons {

    private final Map<String, String> icons;

    public AdminIcons(ObjectMapper mapper) throws IOException {
        try (InputStream in = new ClassPathResource("admin/icons.json").getInputStream()) {
            this.icons = mapper.readValue(in.readAllBytes(), new TypeReference<Map<String, String>>() {
            });
        }
    }

    public Map<String, String> all(int size) {
        Map<String, String> out = new HashMap<>();
        for (String name : icons.keySet()) out.put(name, svg(name, size));
        return out;
    }

    public String svg(String name, int size) {
        return "<svg class=\"i\" viewBox=\"0 0 24 24\" width=\"" + size + "\" height=\"" + size
                + "\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" "
                + "stroke-linejoin=\"round\" aria-hidden=\"true\">" + icons.getOrDefault(name, "") + "</svg>";
    }
}
