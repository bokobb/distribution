package com.confectionery.distribution.admin;

import org.springframework.ui.Model;

/** Шапка страницы: раздел меню, заголовок и пояснение под ним. */
final class AdminPage {

    private AdminPage() {
    }

    static void head(Model model, String sec, String title, String sub) {
        model.addAttribute("sec", sec);
        model.addAttribute("title", title);
        model.addAttribute("sub", sub);
    }

    /** Безопасный адрес возврата: только внутри админки. */
    static String back(String back, String fallback) {
        return back != null && back.startsWith("/admin") && !back.startsWith("//") ? back : fallback;
    }
}
