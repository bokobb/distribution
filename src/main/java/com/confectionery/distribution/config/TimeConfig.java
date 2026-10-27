package com.confectionery.distribution.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;
import java.time.ZoneId;

/** Часы системы: «сегодня», «завтра» и время в истории — по Алматы. В тестах часы подменяются. */
@Configuration
public class TimeConfig {

    public static final ZoneId ZONE = ZoneId.of("Asia/Almaty");

    @Bean
    public Clock clock() {
        return Clock.system(ZONE);
    }
}
