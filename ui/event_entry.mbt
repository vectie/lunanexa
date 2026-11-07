///|
/// Public navigation only. This QR never contains a session or API credential.
fn event_entry_card(state : ConsoleState) -> @rabbita.Html {
  let panel = state.event_trial
  if !panel.public_origin.has_prefix("https://") {
    return @html.nothing
  }
  let url = panel.public_origin + "/user/?trial=event"
  let qr = @qr.encode_medium(url)
  let size = qr.size()
  let path = StringBuilder()
  for y in 0..<size {
    for x in 0..<size {
      if qr.is_black(x, y) {
        path.write_string("M\{x+4} \{y+4}h1v1h-1z")
      }
    }
  }
  @html.details([
    @html.summary(
      localized(
        state.locale,
        "Public registration QR and link",
        "公开报名二维码与链接",
      ),
    ),
    @html.p(
      localized(
        state.locale,
        "Share this public link, never a personal API connection QR. Registration grants shared trial access only during an open event window; machine approval is separate.",
        "可分享此报名码，不要分享个人 API 连接码。仅在活动开放时间内发放共享试用；机器审批独立进行。",
      ),
    ),
    @html.a(href=url, target=Blank, rel="noopener noreferrer", url),
    @html.div(
      attrs=@html.Attrs::build()
        .role("img")
        .aria_label(
          localized(
            state.locale,
            "Public event registration QR",
            "公开活动报名二维码",
          ),
        ),
      [
        @svg.svg(
          width=256,
          height=256,
          view_box="0 0 \{size+8} \{size+8}",
          attrs=@svg.Attrs::build()
            .style("max-width", "100%")
            .style("height", "auto"),
          [
            @svg.rect(x=0, y=0, width=size + 8, height=size + 8, fill="white"),
            @svg.path(
              d=path.to_string(),
              attrs=@svg.Attrs::build().fill("black"),
            ),
          ],
        ),
      ],
    ),
  ])
}
