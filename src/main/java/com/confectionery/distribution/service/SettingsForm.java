package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.CompanySettings;
import lombok.Getter;
import lombok.Setter;

/** Форма настроек компании. Галочка не отмечена — поле не приходит, значит false. */
@Getter
@Setter
public class SettingsForm {
    private String visitRadius;
    private String gpsInterval;
    private String workStart;
    private String workEnd;
    private boolean shelfPhoto;
    private boolean refuseReason;
    private int deliveryDays = 1;
    private String defaultLimit;
    private boolean credit;
    private boolean approval;
    /** «cash» — магазин на проверке только с оплатой при доставке, «credit» — в долг до лимита сразу. */
    private String firstOrder = "cash";
    private boolean overdueBlock;
    private String overdueDays;
    private String overdueAmount;
    private boolean unblockDirector;
    private boolean unblockOperator;
    private boolean underpay;
    private boolean discount;
    private String cashTolerance;
    private boolean kaspi;
    private String crmClient;
    private boolean autoReceipt;

    public static SettingsForm of(CompanySettings st, Company c) {
        SettingsForm f = new SettingsForm();
        f.visitRadius = String.valueOf(st.getVisitRadius());
        f.gpsInterval = String.valueOf(st.getGpsInterval());
        f.workStart = st.getWorkStart().toString();
        f.workEnd = st.getWorkEnd().toString();
        f.shelfPhoto = st.isShelfPhotoRequired();
        f.refuseReason = st.isRefuseReasonRequired();
        f.deliveryDays = st.getDeliveryDays();
        f.defaultLimit = String.valueOf(st.getDefaultCreditLimit());
        f.credit = st.isAllowCredit();
        f.approval = st.isApprovalOverLimit();
        f.firstOrder = st.isFirstOrderCash() ? "cash" : "credit";
        f.overdueBlock = st.isOverdueBlock();
        f.overdueDays = String.valueOf(st.getOverdueDays());
        f.overdueAmount = String.valueOf(st.getOverdueAmount());
        f.unblockDirector = st.isUnblockDirector();
        f.unblockOperator = st.isUnblockOperator();
        f.underpay = st.isUnderpayApproval();
        f.discount = st.isAgentDiscount();
        f.cashTolerance = String.valueOf(st.getCashTolerance());
        f.kaspi = st.isAcceptKaspi();
        f.crmClient = c == null ? null : c.getCrmClient();
        f.autoReceipt = st.isAutoReceipt();
        return f;
    }
}
