package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.domain.TripStatus;
import com.confectionery.distribution.repository.TripRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.List;

@Service
@RequiredArgsConstructor
public class TripService {

    private final TripRepository trips;
    private final Clock clock;

    /** Рейсы сегодня и незакрытые прошлых дней (касса ещё у экспедитора); companyId = null — все видимые. */
    public List<Trip> current(Long companyId) {
        return trips.findByDateOrStatusIn(LocalDate.now(clock), EnumSet.of(TripStatus.ON_ROAD, TripStatus.RETURNED)).stream()
                .filter(t -> companyId == null || companyId.equals(t.getCompanyId()))
                .sorted(Comparator.comparing((Trip t) -> t.getStatus().ordinal()).thenComparing(Trip::getNumber))
                .toList();
    }

    public Trip get(Long id) {
        return trips.findById(id).orElseThrow(NotFoundException::new);
    }
}
