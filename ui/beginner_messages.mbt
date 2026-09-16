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
        "Conversion means joining an active non-trial developer organization, not payment or revenue. Aggregate counts contain no prompts or personal content.",
        "转正指加入有效的非试用开发者组织，不代表付款或收入。聚合统计不包含提示词或个人内容。",
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
