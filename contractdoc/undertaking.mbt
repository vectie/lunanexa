///|
/// The approved attachment is a distinct source document, not a renamed
/// bilateral contract. Admission metadata does not add clauses to its text.
pub fn is_undertaking_template(template_id : String) -> Bool {
  template_id == "youthpolicy-device-undertaking-v1"
}

///|
pub fn undertaking_manifest() -> ContractTemplateManifest {
  let fields = [
    field(
      "lessee.name",
      MasterLease,
      "承诺单位",
      "Undertaking organization",
      PlainText,
      true,
      120,
      "body/p[@w14:paraId='0E84CC24']/name",
      owner=Some(CustomerMessenger),
    ),
    field(
      "undertaking.signed_date",
      MasterLease,
      "承诺日期",
      "Undertaking date",
      CalendarDate,
      true,
      10,
      "body/p[@w14:paraId='694B4DD1']/date",
      owner=Some(CustomerMessenger),
    ),
    field(
      "lease.start_date",
      MasterLease,
      "使用开始日期（开通信息）",
      "Access start date (admission metadata)",
      CalendarDate,
      true,
      10,
      "admission/start_date",
      owner=Some(ManagerOperator),
    ),
    field(
      "lease.end_date",
      MasterLease,
      "使用结束日期（开通信息）",
      "Access end date (admission metadata)",
      CalendarDate,
      true,
      10,
      "admission/end_date",
      owner=Some(ManagerOperator),
    ),
    field(
      "lease.total_rent",
      MasterLease,
      "租金总额（开通信息）",
      "Total rent (admission metadata)",
      MoneyAmount,
      true,
      32,
      "admission/total_rent",
      owner=Some(ManagerOperator),
    ),
  ]
  {
    contract_version,
    collection_id: "youthpolicy",
    template_id: "youthpolicy-device-undertaking-v1",
    template_version: "v1",
    locale: "zh-CN",
    filename: "device-use-undertaking.docx",
    media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    sha256: "sha256:057cdc0cf25b498d4f4ab28b00e5418fece2db73be4fea76951bf0255b73fffe",
    fillable_filename: "device-use-undertaking.fillable.docx",
    fillable_sha256: "sha256:2035da2e600402e40db697c2134b51ca1d82c76e127e9fb1274d285b0f083af4",
    byte_count: 15897L,
    page_count: 4,
    section_count: 1,
    forms: [
      {
        form: MasterLease,
        title_zh_cn: "设备使用承诺函",
        title_en: "Equipment use undertaking",
        field_ids: fields.map(item => item.field_id),
      },
    ],
    fields,
  }
}

///|
fn ContractPacket::undertaking_date_part(
  self : ContractPacket,
  part : String,
) -> String {
  let date = self.value("undertaking.signed_date").unwrap_or("")
  if !valid_calendar_date(date) {
    return ""
  }
  match part {
    "year" => date[:4].to_owned()
    "month" => date[5:7].to_owned()
    "day" => date[8:10].to_owned()
    _ => ""
  }
}
