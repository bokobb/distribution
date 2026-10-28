package com.confectionery.distribution.api;

import org.springframework.http.HttpStatus;

/** Ответ приложению с кодом и текстом для человека — {"message": "…"} (MobileApiAdvice). */
public class ApiException extends RuntimeException {

    private final HttpStatus status;

    public ApiException(HttpStatus status, String message) {
        super(message);
        this.status = status;
    }

    public HttpStatus getStatus() {
        return status;
    }
}
