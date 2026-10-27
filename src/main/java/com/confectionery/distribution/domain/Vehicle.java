package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

@Getter
@Setter
@Accessors(chain = true)
public class Vehicle {
    private Long id;
    private Company company;
    private String plate;
    private String model;
    private Employee expeditor;
}
