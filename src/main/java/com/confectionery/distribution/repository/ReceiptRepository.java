package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Receipt;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ReceiptRepository extends JpaRepository<Receipt, Long> {
    List<Receipt> findAllByOrderByDateDescIdDesc();
}
