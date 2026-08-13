///|
fn marker_name(marker : String) -> String {
  marker[2:marker.length() - 2].to_owned()
}

///|
fn selected(value : String?, expected : String) -> String {
  if value == Some(expected) {
    "☒"
  } else {
    "□"
  }
}

///|
fn clear_if_missing(value : String?) -> String {
  value.unwrap_or("")
}

///|
fn lease_date(packet : ContractPacket, tier : String, which : String) -> String {
  if packet.value("lease.tier") == Some(tier) {
    packet.value("lease.\{which}_date").unwrap_or("")
  } else {
    ""
  }
}

///| Maps one physical marker to an authenticated packet value, an exact

///|
/// source choice glyph, or the source's blank value. It never authors prose.
pub fn ContractPacket::marker_value(
  self : ContractPacket,
  marker : String,
) -> String raise ContractDocumentError {
  if !marker.has_prefix("{{") || !marker.has_suffix("}}") {
    raise InvalidInput("invalid contract marker")
  }
  let name = marker_name(marker)
  if name.has_suffix(".mark") {
    return match name {
      "lease.day.mark" => selected(self.value("lease.tier"), "日租")
      "lease.week.mark" => selected(self.value("lease.tier"), "周租")
      "lease.month.mark" => selected(self.value("lease.tier"), "月租")
      "lease.quarter.mark" => selected(self.value("lease.tier"), "季租")
      "lease.year.mark" => selected(self.value("lease.tier"), "年租")
      "lease.payment.month.mark" =>
        selected(self.value("lease.payment_schedule"), "按月支付")
      "lease.payment.quarter.mark" =>
        selected(self.value("lease.payment_schedule"), "按季支付")
      "lease.payment.once.mark" =>
        selected(self.value("lease.payment_schedule"), "一次性支付")
      "reservation.lease.day.mark" =>
        selected(self.value("reservation.lease_type"), "日租")
      "reservation.lease.week.mark" =>
        selected(self.value("reservation.lease_type"), "周租")
      "reservation.lease.month.mark" =>
        selected(self.value("reservation.lease_type"), "月租")
      "reservation.lease.quarter.mark" =>
        selected(self.value("reservation.lease_type"), "季租")
      "reservation.lease.year.mark" =>
        selected(self.value("reservation.lease_type"), "年租")
      "reservation.new.yes.mark" =>
        selected(self.value("reservation.new_district_enterprise"), "是")
      "reservation.new.no.mark" =>
        selected(self.value("reservation.new_district_enterprise"), "否")
      "reservation.promotion.yes.mark" =>
        selected(self.value("reservation.promotion_requested"), "是")
      "reservation.promotion.no.mark" =>
        selected(self.value("reservation.promotion_requested"), "否")
      "reservation.payment.prepaid.mark" =>
        selected(self.value("reservation.payment_method"), "短租全额预付")
      "reservation.payment.month.mark" =>
        selected(self.value("reservation.payment_method"), "长租按月支付")
      "reservation.payment.quarter.mark" =>
        selected(self.value("reservation.payment_method"), "长租按季支付")
      "reservation.payment.once.mark" =>
        selected(self.value("reservation.payment_method"), "一次性支付")
      "reservation.schedule.approved.mark" =>
        selected(
          self.value("reservation.operator_schedule_decision"),
          "同意申请",
        )
      "reservation.schedule.conflict.mark" =>
        selected(
          self.value("reservation.operator_schedule_decision"),
          "档期冲突",
        )
      "reservation.discount.none.mark" =>
        selected(self.value("reservation.operator_discount"), "无优惠")
      "reservation.discount.promotion.mark" =>
        selected(
          self.value("reservation.operator_discount"),
          "招商首单优惠",
        )
      "reservation.discount.renewal.mark" =>
        selected(self.value("reservation.operator_discount"), "续约优惠")
      "access.open.mark" =>
        selected(self.value("access.operation"), "权限开通")
      "access.close.mark" =>
        selected(self.value("access.operation"), "权限关停")
      "violation.minor.mark" =>
        selected(self.value("violation.level"), "轻微违规")
      "violation.general.mark" =>
        selected(self.value("violation.level"), "一般违规")
      "violation.severe.mark" =>
        selected(self.value("violation.level"), "严重违规")
      "violation.illegal.mark" =>
        selected(self.value("violation.level"), "涉嫌违法")
      "violation.warning.mark" =>
        selected(self.value("violation.measure"), "书面警告")
      "violation.pause.mark" =>
        selected(self.value("violation.measure"), "暂停访问权限")
      "violation.terminate.mark" =>
        selected(self.value("violation.measure"), "立即终止租赁协议")
      "violation.other.mark" =>
        selected(self.value("violation.measure"), "其他")
      "damage.minor.mark" =>
        selected(self.value("damage.level"), "轻微故障")
      "damage.general.mark" =>
        selected(self.value("damage.level"), "一般损坏")
      "damage.severe.mark" =>
        selected(self.value("damage.level"), "严重损坏")
      "damage.lessor.mark" =>
        selected(
          self.value("damage.responsibility"),
          "甲方责任（非人为正常故障）",
        )
      "damage.lessee.mark" =>
        selected(
          self.value("damage.responsibility"),
          "乙方责任（违规操作导致）",
        )
      "damage.pause.mark" =>
        selected(
          self.value("damage.other_treatment"),
          "暂停权限至维修完成",
        )
      "damage.terminate.mark" =>
        selected(self.value("damage.other_treatment"), "终止租赁协议")
      "damage.extend.mark" =>
        selected(self.value("damage.other_treatment"), "顺延租期")
      "settlement.day.mark" =>
        selected(self.value("settlement.lease_type"), "日租")
      "settlement.week.mark" =>
        selected(self.value("settlement.lease_type"), "周租")
      "settlement.month.mark" =>
        selected(self.value("settlement.lease_type"), "月租")
      "settlement.quarter.mark" =>
        selected(self.value("settlement.lease_type"), "季租")
      "settlement.year.mark" =>
        selected(self.value("settlement.lease_type"), "年租")
      "settlement.none.mark" =>
        selected(self.value("settlement.other_fee_type"), "无")
      "settlement.compensation.mark" =>
        selected(self.value("settlement.other_fee_type"), "赔偿费用")
      "settlement.penalty.mark" =>
        selected(self.value("settlement.other_fee_type"), "违约金")
      "settlement.other.mark" =>
        selected(self.value("settlement.other_fee_type"), "其他")
      "termination.refund.mark" =>
        selected(self.value("termination.balance_type"), "应退还金额")
      "termination.additional.mark" =>
        selected(self.value("termination.balance_type"), "应补缴金额")
      "termination.approved.mark" =>
        selected(
          self.value("termination.review_decision"),
          "同意提前退租，按上述标准结算",
        )
      "termination.rejected.mark" =>
        selected(self.value("termination.review_decision"), "不同意")
      _ => raise InvalidInput("unknown contract choice marker")
    }
  }
  match name {
    "lease.day.start" => lease_date(self, "日租", "start")
    "lease.week.start" => lease_date(self, "周租", "start")
    "lease.month.start" => lease_date(self, "月租", "start")
    "lease.quarter.start" => lease_date(self, "季租", "start")
    "lease.year.start" => lease_date(self, "年租", "start")
    "lease.day.end" => lease_date(self, "日租", "end")
    "lease.week.end" => lease_date(self, "周租", "end")
    "lease.month.end" => lease_date(self, "月租", "end")
    "lease.quarter.end" => lease_date(self, "季租", "end")
    "lease.year.end" => lease_date(self, "年租", "end")
    _ => clear_if_missing(self.value(name))
  }
}

///|
pub fn ContractPacket::marker_replacements(
  self : ContractPacket,
  markers : Array[String],
) -> Array[ContractFieldValue] raise ContractDocumentError {
  if self.state != GenerationRequested {
    raise InvalidTransition("contract packet generation was not requested")
  }
  markers.map(marker => { field_id: marker, value: self.marker_value(marker) })
}
