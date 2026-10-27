package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.GpsPoint;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface GpsPointRepository extends JpaRepository<GpsPoint, Long> {
    List<GpsPoint> findByRecordedAtGreaterThanEqualAndRecordedAtLessThanOrderByRecordedAtAsc(LocalDateTime from, LocalDateTime to);
}
