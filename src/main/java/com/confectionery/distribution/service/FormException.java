package com.confectionery.distribution.service;

/** Форма заполнена неверно: текст — для человека, страница показывает его над формой. Ничего не сохранено. */
public class FormException extends RuntimeException {

    public FormException(String message) {
        super(message);
    }
}
