///|
/// Familiar commands whose object is already visible beside the control.
pub(all) enum Icon {
  Refresh
  Copy
}

///|
/// Local Rabbita rendering of MoonVis's refresh/copy source geometry from
/// docs/assets/icon-language/svg (2026-10-13). No runtime MoonVis dependency.
fn glyph(icon : Icon) -> @rabbita.Html {
  @html.span(
    class="ln-command-glyph",
    attrs=@html.Attrs::build().aria_hidden("true"),
    [
      @svg.svg(
        width=18,
        height=18,
        view_box="0 0 24 24",
        attrs=@svg.Attrs::build()
          .fill("none")
          .stroke("currentColor")
          .stroke_width("1.65")
          .stroke_linecap("round")
          .stroke_linejoin("round"),
        match icon {
          Refresh =>
            [
              @svg.path(
                d="M20 4v6h-6M4 20v-6h6M20 10a8 8 0 0 0-14-5M4 14a8 8 0 0 0 14 5",
              ),
            ]
          Copy =>
            [
              @svg.path(
                d="M10 8h9a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2ZM16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3",
              ),
            ]
        },
      ),
    ],
  )
}

///|
/// Render a named command with a decorative icon and a hover/focus tooltip.
/// The caller keeps any task outcome or loading message beside the object.
pub fn icon_button(
  icon : Icon,
  label : String,
  on_click : @rabbita.Cmd,
  disabled? : Bool = false,
  busy? : Bool = false,
) -> @rabbita.Html {
  @html.button(
    type_="button",
    class="ln-icon-button",
    disabled=disabled || busy,
    attrs=@html.Attrs::build()
      .aria_label(label)
      .aria_busy(if busy { "true" } else { "false" }),
    on_click~,
    [
      glyph(icon),
      @html.span(
        class="ln-command-tooltip",
        attrs=@html.Attrs::build().aria_hidden("true"),
        label,
      ),
    ],
  )
}

///|
/// Shared interaction treatment; color inherits the consuming surface.
pub fn styles() -> String {
  let css =
    #|.ln-advanced{min-width:0;margin:.65rem 0;border-top:1px solid var(--line,currentColor)}.ln-advanced>summary{min-height:44px;padding:.7rem .2rem;cursor:pointer;font-weight:650;color:inherit}.ln-advanced>summary:focus-visible{outline:2px solid currentColor;outline-offset:3px}.ln-advanced-content{min-width:0;padding:.35rem 0 .8rem}.ln-advanced-content>.field,.ln-advanced-content>.field-group{margin-bottom:.8rem}.form-grid>.ln-advanced,.offline-form-grid>.ln-advanced,.operation-form>.ln-advanced{grid-column:1/-1}
    #|.ln-icon-button{position:relative;display:inline-flex;flex:none;align-items:center;justify-content:center;min-width:44px;min-height:44px;width:44px;height:44px;padding:0;border:1px solid transparent;border-radius:.5rem;background:transparent;color:inherit;cursor:pointer}
    #|.ln-icon-button:not(:disabled):hover{background:color-mix(in srgb,currentColor 9%,transparent)}
    #|.ln-icon-button:focus-visible{outline:2px solid currentColor;outline-offset:3px}
    #|.ln-icon-button:disabled{opacity:.45;cursor:not-allowed}.ln-command-glyph{display:inline-flex;pointer-events:none}
    #|.ln-icon-button[aria-busy=true] .ln-command-glyph{animation:ln-refresh 1.2s linear infinite}
    #|.ln-command-tooltip{position:absolute;z-index:50;top:calc(100% + 6px);right:0;width:max-content;max-width:min(18rem,75vw);padding:.35rem .55rem;border-radius:.35rem;background:#17282b;color:#fff;font:500 .75rem/1.4 system-ui;white-space:normal;text-align:left;pointer-events:none;visibility:hidden;opacity:0}.ln-icon-button:hover .ln-command-tooltip,.ln-icon-button:focus-visible .ln-command-tooltip{visibility:visible;opacity:1}
    #|@keyframes ln-refresh{to{transform:rotate(360deg)}}@media(prefers-reduced-motion:reduce){.ln-icon-button[aria-busy=true] .ln-command-glyph{animation:none}}
  css
}

///|
/// Native disclosure preserves keyboard support and child field values.
pub fn advanced(
  title : String,
  children : Array[@rabbita.Html],
) -> @rabbita.Html {
  @html.details(class="ln-advanced", [
    @html.summary(title),
    @html.div(class="ln-advanced-content", children),
  ])
}
