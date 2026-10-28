package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Visit;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface VisitRepository extends JpaRepository<Visit, Long> {
    List<Visit> findByStartedAtGreaterThanEqualAndStartedAtLessThan(LocalDateTime from, LocalDateTime to);

    Optional<Visit> findByUuid(UUID uuid);

    List<Visit> findByAgentIdAndStartedAtGreaterThanEqualAndStartedAtLessThanOrderByStartedAtAsc(Long agentId,
                                                                                                  LocalDateTime from,
                                                                                                  LocalDateTime to);
}
