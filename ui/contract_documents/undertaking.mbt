///|
/// Which rental routes a customer may pick between.
///
/// The undertaking path is live; the traditional bilateral rental contract is
/// not offered yet and stays visible but disabled, so the choice itself is
/// discoverable. Flip this to true to re-enable the contract route.
pub let traditional_contract_route_available : Bool = false

///|
/// The disabled contract route is still shown once, with its reason, so the menu
/// does not silently lose an option the customer was told about.
fn contract_route_unavailable_copy(locale : @i18n.Locale) -> String {
  copy(
    locale, "Traditional rental contract · bilateral execution (temporarily unavailable)",
    "传统租赁合同 · 双方签署（暂未开放）",
  )
}

///|
/// Resolve by the packet's immutable template identity, never by menu order.
pub fn ContractDocumentsState::current_manifest(
  self : ContractDocumentsState,
) -> @contractdoc.ContractTemplateManifest? {
  let packet = match self.selected_packet_id {
    Some(id) => find_packet(self.packets, id)
    None => self.packets.get(0)
  }
  match packet {
    Some(packet) => {
      for manifest in self.available_manifests {
        if manifest.template_id == packet.template_id {
          return Some(manifest)
        }
      }
      self.manifest.filter(value => value.template_id == packet.template_id)
    }
    None => self.manifest
  }
}

///|
fn undertaking_creation(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
) -> @rabbita.Html {
  if state.actor_owner != CustomerMessenger ||
    state.available_manifests.is_empty() {
    return @html.nothing
  }
  let template_id = state.creation_template_id
  let order_ref = state.creation_order_ref
  let orders = state.available_orders.filter(item => {
    (
      !@contractdoc.is_undertaking_template(template_id) ||
      state.undertaking_order_refs.contains(item.0)
    ) &&
    !state.packets.any(packet => {
      packet.order_ref == item.0 && packet.template_id == template_id
    })
  })
  // Both routes are always listed: the undertaking from whatever manifests are
  // loaded, and the traditional contract as a disabled entry while it is offline.
  let route_options : Array[@html.Html] = [
    @html.option(
      value="",
      selected=template_id == "",
      copy(state.locale, "Choose a document", "请选择办理方式"),
    ),
  ]
  for manifest in state.available_manifests {
    if @contractdoc.is_undertaking_template(manifest.template_id) ||
      traditional_contract_route_available {
      route_options.push(
        @html.option(
          value=manifest.template_id,
          selected=template_id == manifest.template_id,
          if manifest.template_id == "youthpolicy-device-undertaking-ofl-v2" {
            copy(
              state.locale,
              "Equipment undertaking · open-font edition · Party A approval",
              "设备使用承诺函 · 开源字体新版 · 甲方审批",
            )
          } else if manifest.template_id == "youthpolicy-device-undertaking-v1" &&
            state.available_manifests.any(item => {
              item.template_id == "youthpolicy-device-undertaking-ofl-v2"
            }) {
            copy(
              state.locale,
              "Equipment undertaking · original edition · existing orders",
              "设备使用承诺函 · 原版 · 历史订单",
            )
          } else if @contractdoc.is_undertaking_template(manifest.template_id) {
            copy(
              state.locale,
              "Equipment undertaking · Party A approval",
              "设备使用承诺函 · 甲方审批",
            )
          } else {
            copy(
              state.locale,
              "Traditional rental contract · bilateral execution",
              "传统租赁合同 · 双方签署",
            )
          },
        ),
      )
    }
  }
  if !traditional_contract_route_available {
    route_options.push(
      @html.option(
        value="traditional-rental-contract-unavailable",
        disabled=true,
        contract_route_unavailable_copy(state.locale),
      ),
    )
  }
  @html.section(class="contract-workspace", [
    @html.div(class="contract-form-panel", [
      @html.h2(
        copy(
          state.locale,
          "Choose your rental document",
          "选择租赁办理方式",
        ),
      ),
      @html.p(
        copy(
          state.locale,
          "Traditional bilateral contract or a tenant-signed undertaking reviewed by Party A. Both retain payment, capacity and access checks. The traditional contract route is temporarily unavailable.",
          "可选传统双方合同，或使用方签章、甲方审批的承诺函。两种方式均保留付款、资源与权限检查。传统合同方式暂未开放。",
        ),
      ),
      @html.div(class="contract-field-grid", [
        @html.div(class="contract-field", [
          @html.label(
            for_="rental-document-template",
            copy(state.locale, "Document path", "办理方式"),
          ),
          @html.select(
            id="rental-document-template",
            on_change=text_command(emit, value => SelectCreationTemplate(value)),
            route_options,
          ),
        ]),
        @html.div(class="contract-field", [
          @html.label(
            for_="rental-document-order",
            copy(state.locale, "Your rental order", "关联租赁订单"),
          ),
          @html.select(
            id="rental-document-order",
            on_change=text_command(emit, value => SelectCreationOrder(value)),
            [
              @html.option(
                value="",
                selected=order_ref == "",
                copy(
                  state.locale,
                  "Choose an existing order",
                  "选择已有订单",
                ),
              ),
              ..orders.map(item => {
                @html.option(value=item.0, selected=order_ref == item.0, item.1)
              }),
            ],
          ),
        ]),
      ]),
      @html.p(
        copy(
          state.locale,
          "Organization and order information are reused where verified. Review the original document, generate it, sign and stamp it, then submit the scan for approval. Approval is not a second signature.",
          "已核实的单位与订单资料自动带入。审阅原文、生成文件、签字盖章后提交扫描件审批；甲方审批不等于再次签署。",
        ),
      ),
      if orders.is_empty() {
        @html.p(
          copy(
            state.locale,
            "No eligible new order is available. Ask Party A to confirm the fixed tariff, or reopen the existing packet below; revisions do not need a second order.",
            "当前没有符合条件的新订单。请甲方确认固定档位报价，或在下方打开已有资料包；修订无需重复下单。",
          ),
        )
      } else {
        @html.nothing
      },
      @html.button(
        type_="button",
        class="primary-button",
        disabled=state.loading ||
          template_id == "" ||
          !orders.any(item => item.0 == order_ref),
        on_click=command(emit, CreatePacket(template_id, order_ref)),
        copy(state.locale, "Prepare document", "准备文档"),
      ),
    ]),
  ])
}

///|
fn undertaking_scans(
  state : ContractDocumentsState,
  packet_id : String,
) -> Array[(String, String, String, Int64)] {
  guard find_packet(state.packets, packet_id) is Some(packet) else { return [] }
  let rendered_at = packet.artifacts.fold(init=0L, (latest, artifact) => {
    latest.max(artifact.generated_unix_ms)
  })
  state.signed_artifacts.filter(item => {
    item.0 == packet.order_ref && item.3 >= rendered_at
  })
}

///|
fn undertaking_confirmation(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  action : ContractDocumentConfirmation,
) -> @rabbita.Html {
  let submitting = action is SubmitUndertaking(_, _, _, _)
  let ready = match action {
    SubmitUndertaking(id, _, artifact, date) =>
      date.trim() != "" &&
      undertaking_scans(state, id).any(item => item.1 == artifact)
    ReviseUndertaking(_, _) => true
    _ => false
  }
  @html.div(class="modal-backdrop", [
    @html.section(
      class="confirmation-dialog",
      attrs=@html.Attrs::build().role("alertdialog").aria_modal("true"),
      [
        @html.h2(
          if submitting {
            copy(
              state.locale,
              "Submit signed undertaking",
              "提交已签章承诺函",
            )
          } else {
            copy(
              state.locale,
              "Revise this undertaking?",
              "修订本承诺函？",
            )
          },
        ),
        @html.p(
          if submitting {
            copy(
              state.locale,
              "Select your uploaded signed and stamped scan. Party A reviews it before activation; full payment and resource checks still apply.",
              "选择已上传的使用方签字盖章扫描件，甲方审核后才可开通；全额付款与资源检查仍须通过。",
            )
          } else {
            copy(
              state.locale,
              "Current confirmation, generated documents and pending approval become invalid. Edit the new revision, regenerate and sign again; old scans cannot authorize it.",
              "当前确认、生成物与待审批申请将失效。修改新版本后须重新生成并签章，旧扫描件不能授权新版本。",
            )
          },
        ),
        match action {
          SubmitUndertaking(id, _, artifact, date) => {
            let order = find_packet(state.packets, id).map_or("", packet => {
              packet.order_ref
            })
            @html.div(class="contract-field-grid", [
              @html.div(class="contract-field", [
                @html.label(
                  for_="undertaking-scan",
                  copy(state.locale, "Signed scan", "签章扫描件"),
                ),
                @html.select(
                  id="undertaking-scan",
                  on_change=text_command(emit, value => {
                    ConfirmationInputChanged(EvidenceDigest, value)
                  }),
                  [
                    @html.option(
                      value="",
                      selected=artifact == "",
                      copy(
                        state.locale,
                        "Choose a scanned document",
                        "选择已通过扫描检查的文件",
                      ),
                    ),
                    ..undertaking_scans(state, id).map(item => {
                      @html.option(
                        value=item.1,
                        selected=artifact == item.1,
                        item.2,
                      )
                    }),
                  ],
                ),
                @html.button(
                  type_="button",
                  class="quiet-button",
                  disabled=state.loading,
                  on_click=command(emit, UploadUndertakingEvidence(order)),
                  copy(
                    state.locale,
                    "Upload signed scan",
                    "上传签章扫描件",
                  ),
                ),
              ]),
              dialog_text_input(
                emit,
                "undertaking-signed-date",
                copy(
                  state.locale,
                  "Date signed (YYYY-MM-DD)",
                  "签署日期（YYYY-MM-DD）",
                ),
                date,
                SignedOn,
              ),
            ])
          }
          _ => @html.nothing
        },
        @html.div(class="dialog-actions", [
          @html.button(
            type_="button",
            class="quiet-button",
            on_click=command(emit, DismissConfirmation),
            copy(state.locale, "Back", "返回"),
          ),
          @html.button(
            type_="button",
            class="primary-button",
            disabled=state.loading || !ready,
            on_click=command(emit, ConfirmAction(action)),
            if submitting {
              copy(
                state.locale,
                "Submit for Party A approval",
                "提交甲方审批",
              )
            } else {
              copy(state.locale, "Create revision", "开始修订")
            },
          ),
        ]),
      ],
    ),
  ])
}
