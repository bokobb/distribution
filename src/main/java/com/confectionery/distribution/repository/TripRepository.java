package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.domain.TripStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface TripRepository extends JpaRepository<Trip, Long> {
    /** Рейсы дня и все незакрытые (касса ещё у экспедитора). */
    List<Trip> findByDateOrStatusIn(LocalDate date, Collection<TripStatus> statuses);

    /** Рейсы, которые ещё загружаются, на будущие дни. */
    List<Trip> findByStatusAndDateAfter(TripStatus status, LocalDate date);

    Optional<Trip> findFirstByExpeditorAndDateAndStatusOrderByIdDesc(Employee expeditor, LocalDate date, TripStatus status);

    boolean existsByCompanyIdAndNumber(Long companyId, String number);
}
