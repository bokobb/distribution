package com.confectionery.distribution.api;

import com.confectionery.distribution.service.FormException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

/** Ошибки адресов приложения — всегда {"message": "…"}: приложение показывает текст как есть. */
@RestControllerAdvice(basePackageClasses = MobileApiAdvice.class)
public class MobileApiAdvice {

    public record ApiError(String message) {
    }

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiError> api(ApiException e) {
        return ResponseEntity.status(e.getStatus()).body(new ApiError(e.getMessage()));
    }

    @ExceptionHandler(FormException.class)
    public ResponseEntity<ApiError> form(FormException e) {
        return ResponseEntity.badRequest().body(new ApiError(e.getMessage()));
    }

    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<ApiError> status(ResponseStatusException e) {
        return ResponseEntity.status(e.getStatusCode())
                .body(new ApiError(e.getStatusCode().value() == 404 ? "Не найдено" : "Ошибка запроса"));
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiError> unreadable(HttpMessageNotReadableException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(new ApiError("Неверный запрос — обновите приложение"));
    }
}
