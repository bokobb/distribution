package com.confectionery.distribution.service;

import java.io.Serializable;
import java.security.SecureRandom;

/**
 * Временный пароль, выданный сотруднику: показывается один раз, в базе — только его хеш. При первом
 * входе сотрудник меняет его на свой.
 */
public record IssuedPassword(String name, String phone, String password) implements Serializable {

    /** Без похожих знаков (0/o, 1/l/i): пароль диктуют по телефону и набирают на телефоне. */
    private static final String ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789";
    private static final SecureRandom RANDOM = new SecureRandom();

    static String generate() {
        StringBuilder sb = new StringBuilder(8);
        for (int i = 0; i < 8; i++) sb.append(ALPHABET.charAt(RANDOM.nextInt(ALPHABET.length())));
        return sb.toString();
    }
}
