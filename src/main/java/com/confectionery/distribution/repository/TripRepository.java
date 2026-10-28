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

    /** Незакрытые рейсы на будущие дни. */
    List<Trip> findByStatusInAndDateAfter(Collection<TripStatus> statuses, LocalDate date);

    Optional<Trip> findFirstByExpeditorAndDateAndStatusInOrderByIdDesc(Employee expeditor, LocalDate date, Collection<TripStatus> statuses);

    /** Рейсы экспедитора с этими статусами — для его телефона. */
    List<Trip> findByExpeditorIdAndStatusInOrderByDateAscNumberAsc(Long expeditorId, Collection<TripStatus> statuses);

    boolean existsByCompanyIdAndNumber(Long companyId, String number);
}
