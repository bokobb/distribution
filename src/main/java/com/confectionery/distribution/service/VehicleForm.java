package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Vehicle;
import lombok.Getter;
import lombok.Setter;

/** Форма машины: гос. номер, модель, закреплённый экспедитор. */
@Getter
@Setter
public class VehicleForm {
    private Long id;
    private String plate;
    private String model;
    private Long expeditorId;

    public static VehicleForm of(Vehicle v) {
        VehicleForm f = new VehicleForm();
        f.id = v.getId();
        f.plate = v.getPlate();
        f.model = v.getModel();
        f.expeditorId = v.getExpeditor() == null ? null : v.getExpeditor().getId();
        return f;
    }
}
