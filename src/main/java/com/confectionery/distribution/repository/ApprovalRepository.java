package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Approval;
import com.confectionery.distribution.domain.ApprovalKind;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface ApprovalRepository extends JpaRepository<Approval, Long> {

    @EntityGraph(attributePaths = {"outlet", "order"})
    List<Approval> findByKindAndDecisionIsNullOrderByCreatedAtAsc(ApprovalKind kind);

    @EntityGraph(attributePaths = {"outlet", "company"})
    List<Approval> findByDecidedAtGreaterThanEqualOrderByDecidedAtDesc(LocalDateTime from);

    boolean existsByKindAndOrderIdAndDecisionIsNull(ApprovalKind kind, Long orderId);
}
