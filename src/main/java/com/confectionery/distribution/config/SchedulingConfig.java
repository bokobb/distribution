package com.confectionery.distribution.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/** Ночные задачи сервера (удаление старых точек GPS и журнала — TrackCleanup). */
@Configuration
@EnableScheduling
public class SchedulingConfig {
}
