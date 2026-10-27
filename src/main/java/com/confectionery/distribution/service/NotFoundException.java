package com.confectionery.distribution.service;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/** Записи нет — или она чужой компании: для пользователя это одно и то же (404). */
public class NotFoundException extends ResponseStatusException {
    public NotFoundException() {
        super(HttpStatus.NOT_FOUND);
    }
}
