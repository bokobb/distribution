package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.domain.TripStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.Collection;
import java.util.List;

public interface TripRepository extends JpaRepository<Trip, Long> {
    /** Рейсы дня и все незакрытые (касса ещё у экспедитора). */
    List<Trip> findByDateOrStatusIn(LocalDate date, Collection<TripStatus> statuses);
}
