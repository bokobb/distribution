package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.util.ArrayList;
import java.util.List;

@Getter
@Setter
@Accessors(chain = true)
public class Region {
    private Long id;
    private Company company;
    private String name;
    private List<Route> routes = new ArrayList<>();
}
