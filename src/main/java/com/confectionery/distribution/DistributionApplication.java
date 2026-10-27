package com.confectionery.distribution;

import com.confectionery.distribution.config.TimeConfig;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.util.TimeZone;

@SpringBootApplication
public class DistributionApplication {

    public static void main(String[] args) {
        // Время в базе хранится местное, без пояса: сервер должен жить по Алматы, где бы ни стоял.
        TimeZone.setDefault(TimeZone.getTimeZone(TimeConfig.ZONE));
        SpringApplication.run(DistributionApplication.class, args);
    }
}
