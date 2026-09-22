///|
extern "js" fn contract_poll_fetch(
  endpoint : String,
  token : String,
  subject : String,
  organization : String,
) -> @js.Promise =
  #| async (endpoint, token, subject, organization) => {
  #|   const controller = new AbortController();
  #|   const timer = setTimeout(() => controller.abort(), 10000);
  #|   try {
  #|     const headers = {Accept: "application/json", Authorization: `Bearer ${token}`};
  #|     if (subject) headers["X-LunaNexa-Subject"] = subject;
  #|     if (organization) headers["X-LunaNexa-Organization"] = organization;
  #|     const response = await fetch(endpoint.replace(/\/$/, "") + "/v1/contract-documents/self", {
  #|       headers, signal: controller.signal, credentials: "same-origin", cache: "no-store", redirect: "error"
  #|     });
  #|     if (!response.ok) throw new Error("contract refresh failed");
  #|     return await response.text();
  #|   } finally { clearTimeout(timer); }
  #| }

///|
fn schedule_contract_preview(
  model : AppModel,
  documents : @contract_documents.ContractDocumentsState,
  delay_ms : Int,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  let (next, preview) = schedule_contract_preview_only(
    model, documents, delay_ms, emit,
  )
  let selected = documents.packets.search_by(packet => {
    Some(packet.packet_id) == documents.selected_packet_id
  })
  match selected {
    Some(index) => {
      let (polling, poll) = start_contract_poll(
        next,
        documents.packets[index],
        emit,
      )
      (polling, @rabbita.batch([preview, poll]))
    }
    None =>
      (
        {
          ..next,
          contract_poll_generation: next.contract_poll_generation + 1L,
        },
        preview,
      )
  }
}

///|
fn contract_poll_active(
  model : AppModel,
  generation : Int64,
  packet_id : String,
) -> Bool {
  model.contract_poll_generation == generation &&
  model.portal.route == ContractDocuments &&
  model.portal.contract_documents.selected_packet_id == Some(packet_id) &&
  !model.demo_mode &&
  !model.token.is_empty()
}

///|
fn contract_poll_timer(
  generation : Int64,
  packet_id : String,
  remaining : Int,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(message => emit(message), async fn() noraise {
    ignore(contract_preview_delay_promise(2000).wait()) catch {
      _ => ()
    }
    ContractPollDue(generation, packet_id, remaining)
  })
}

///|
fn start_contract_poll(
  model : AppModel,
  packet : @contractdoc.ContractPacket,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  let next = {
    ..model,
    contract_poll_generation: model.contract_poll_generation + 1L,
  }
  if packet.state == GenerationRequested &&
    contract_poll_active(next, next.contract_poll_generation, packet.packet_id) {
    (
      next,
      contract_poll_timer(
        next.contract_poll_generation,
        packet.packet_id,
        150,
        emit,
      ),
    )
  } else {
    (next, @rabbita.none)
  }
}

///|
fn contract_poll_request(
  model : AppModel,
  generation : Int64,
  packet_id : String,
  remaining : Int,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(message => emit(message), async fn() noraise {
    let result = try {
      let packets : Array[@contractdoc.ContractPacket] = @json.from_json(
        @json.parse(
          contract_poll_fetch(
            model.endpoint,
            model.token,
            model.subject_ref,
            @enterprise_ui.selected_organization_header(model.portal).unwrap_or(
              "",
            ),
          )
          .wait()
          .cast(),
        ),
      )
      Ok(packets)
    } catch {
      _ => Err("refresh_failed")
    }
    ContractPollResult(generation, packet_id, remaining, result)
  })
}

///|
fn apply_contract_poll(
  model : AppModel,
  generation : Int64,
  packet_id : String,
  remaining : Int,
  result : Result[Array[@contractdoc.ContractPacket], String],
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  guard contract_poll_active(model, generation, packet_id) else {
    return (model, @rabbita.none)
  }
  let documents = model.portal.contract_documents
  let packet = match result {
    Ok(packets) =>
      packets
      .search_by(packet => packet.packet_id == packet_id)
      .map(index => packets[index])
    Err(_) => None
  }
  let notice = portal_copy(
    model.portal.locale,
    "Automatic refresh stopped. Refresh to check generation again; do not resubmit.",
    "自动刷新已停止。请刷新查看生成进度，无需重新提交。",
  )
  let next_documents = match packet {
    Some(packet) =>
      {
        ..documents,
        packets: replace_contract_packet(documents.packets, packet),
        // Never replace draft_values or selection in a background response.
        success_message: if packet.state == Generated {
          Some(
            portal_copy(
              model.portal.locale,
              "Documents generated. Downloads are ready.",
              "文件已生成，可以下载。",
            ),
          )
        } else {
          documents.success_message
        },
        error_message: if packet.state == GenerationFailed {
          Some(
            portal_copy(
              model.portal.locale,
              "Document generation failed. Review the status before retrying.",
              "文件生成失败，请查看状态后重试。",
            ),
          )
        } else {
          documents.error_message
        },
      }
    None => { ..documents, error_message: Some(notice), }
  }
  let next = {
    ..model,
    portal: { ..model.portal, contract_documents: next_documents, },
  }
  if packet is Some({ state: GenerationRequested, .. }) && remaining > 1 {
    (next, contract_poll_timer(generation, packet_id, remaining - 1, emit))
  } else if packet is Some({ state: GenerationRequested, .. }) {
    (
      {
        ..next,
        portal: {
          ..next.portal,
          contract_documents: { ..next_documents, error_message: Some(notice), },
        },
      },
      @rabbita.none,
    )
  } else {
    (next, @rabbita.none)
  }
}
