///|
priv enum BeginnerMessage {
  TrialTitle
  TrialUnavailable
  TrialBoundary
  AnnouncementTitle
  AnnouncementBoundary
  PublishAnnouncement
}

///|
fn beginner_message(locale : @i18n.Locale, message : BeginnerMessage) -> String {
  let (english, chinese) = match message {
    TrialTitle => ("Trial adoption", "试用与转正概况")
    TrialUnavailable =>
      (
        "Trial statistics unavailable. Refresh after checking controller support.",
        "试用统计暂不可用。请检查控制器支持情况后刷新。",
      )
    TrialBoundary =>
      (
        "Converted: active company membership, not payment or revenue.", "转正：已加入有效企业，不代表付款或收入。",
      )
    AnnouncementTitle => ("Publish platform announcement", "发布平台公告")
    AnnouncementBoundary =>
      (
        "Send plain-text guidance to one tenant only. Review the tenant and expiry before publishing; announcements do not change permissions or quotas.",
        "仅向指定租户发送纯文本说明。发布前请核对租户及到期时间；公告不会修改权限或配额。",
      )
    PublishAnnouncement => ("Publish announcement", "发布公告")
  }
  @i18n.copy(locale, english, chinese)
}
