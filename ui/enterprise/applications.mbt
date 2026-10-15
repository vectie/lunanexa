///|
fn application_cards(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  @html.section(class="application-launcher", [
    @html.style_tag(
      ".application-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:1rem}.application-card{display:flex;flex-direction:column;align-items:flex-start;gap:1rem;min-width:0;padding:1.4rem;border:1px solid var(--line);border-radius:1rem;background:var(--panel)}.application-card.is-selected{border-color:var(--mint)}.application-card img{display:block;width:64px;height:64px;object-fit:contain;border-radius:15px}.application-card h3{margin:0;font-size:1.15rem}.application-card p{margin:0;color:var(--muted);font-size:.9rem}.application-card button{min-height:44px;margin-top:auto;width:100%}.application-settings>summary{cursor:pointer;min-height:44px;display:flex;align-items:center;gap:.5rem}.application-settings>summary:focus-visible{outline:2px solid var(--mint);outline-offset:3px}.application-settings[open]>summary{margin-bottom:1rem}.application-settings-content{display:grid;gap:1rem}.delivery-new-service{margin-top:1rem}.delivery-new-service>summary,.record-main details>summary{min-height:44px;padding:.7rem 0;cursor:pointer}.delivery-new-service>summary:focus-visible,.record-main details>summary:focus-visible{outline:2px solid var(--mint);outline-offset:2px}@media(max-width:1250px){.application-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:540px){.application-grid{grid-template-columns:minmax(0,1fr)}}",
    ),
    @html.h2(enterprise_copy(state.locale, ChooseYourWebide)),
    @html.style_tag(
      ".application-settings>summary{display:list-item;padding:.7rem 0}",
    ),
    @html.div(
      class="application-grid",
      [
        for
          (id, name) in [
            ("comfyui", "ComfyUI"),
            ("desktop-workspace", "MoonDesk"),
            ("moonrobo", "MoonRobo"),
            ("moontown", "MoonTown"),
          ] => {
          let client = state.desktop_clients
            .iter()
            .find_first(client => client.client_id == id)
          let selected = state.desktop_client.map_or(false, current => {
            current.client_id == id
          })
          let direct = client.map_or(false, client => {
            webide_launch_selection(state.select_application_client(client))
            is Some(_)
          })
          // A published shared workspace never falls back to a company's
          // reserved GPU delivery, including while its trial model is down.
          let hosted_comfy = client.map_or(false, current => {
            current.launch_uri.has_suffix("/comfyui/connect")
          })
          let comfy = if id == "comfyui" && !hosted_comfy {
            state.deliveries.operations
            .iter()
            .find_first(operation => {
              operation.stage == "Ready" &&
              operation.expires_at_ms > state.machine_access.now_unix_ms &&
              delivery_launch_template(state.deliveries, operation.operation_id).map_or(
                false,
                template => template.client_id == Some("comfyui"),
              )
            })
          } else {
            None
          }
          let ready = direct || comfy is Some(_)
          let logo = if id == "desktop-workspace" { "moondesk" } else { id }
          @html.article(
            class=if selected {
              "application-card is-selected"
            } else {
              "application-card"
            },
            [
              @html.img(
                src="./apps/\{logo}.svg",
                alt="\{name} logo",
                width=64,
                height=64,
              ),
              @html.h3(name),
              @html.p(
                if ready {
                  copy(state.locale, "Ready", "已就绪")
                } else {
                  match client {
                    None => copy(state.locale, "Not configured", "暂未配置")
                    Some(client) if id == "comfyui" &&
                      !client.launch_uri.has_suffix("/comfyui/connect") =>
                      copy(state.locale, "GPU workspace", "GPU 工作区")
                    Some(client) if !client.contract_ready =>
                      copy(state.locale, "Contract required", "待完成合同")
                    Some(client) if !client.workspace_ready =>
                      copy(
                        state.locale,
                        "Workspace required",
                        "待开通工作区",
                      )
                    Some(client) if !client.models_ready =>
                      copy(
                        state.locale,
                        "Waiting for model",
                        "等待模型就绪",
                      )
                    _ =>
                      copy(
                        state.locale,
                        "Access unavailable",
                        "访问暂不可用",
                      )
                  }
                },
              ),
              @html.button(
                type_="button",
                class=if ready { "primary-button" } else { "quiet-button" },
                disabled=state.loading || (client is None && comfy is None),
                attrs=@html.Attrs::build().aria_pressed(selected.to_string()),
                on_click=command(
                  emit,
                  match comfy {
                    Some(operation) =>
                      Delivery(OpenWorkspace(operation.operation_id))
                    None if direct => OpenApplication(id)
                    None => SelectWebIde(id)
                  },
                ),
                if ready {
                  copy(state.locale, "Open \{name}", "打开 \{name}")
                } else if client is None {
                  copy(state.locale, "Unavailable", "暂未开放")
                } else {
                  copy(state.locale, "Configure \{name}", "配置 \{name}")
                },
              ),
            ],
          )
        }
      ],
    ),
  ])
}
