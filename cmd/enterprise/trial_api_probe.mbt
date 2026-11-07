///|
priv struct TrialApiTestResult {
  ok : Bool
  status : Int32
  elapsed_ms : Int32
  input_tokens : Int32
  output_tokens : Int32
  content : String
} derive(FromJson)

///|
extern "js" fn trial_api_test_promise(
  secret : String,
  model : String,
) -> @js.Promise =
  #| async (secret, model) => {
  #|   const started = performance.now();
  #|   const controller = new AbortController();
  #|   const timer = setTimeout(() => controller.abort(), 120000);
  #|   let status = 0;
  #|   try {
  #|     const models = await fetch(new URL('/trial/v1/models', location.origin), {
  #|       credentials:'omit', redirect:'error', cache:'no-store', signal:controller.signal,
  #|       headers:{'Authorization':'Bearer ' + secret}
  #|     });
  #|     status = models.status;
  #|     if (!models.ok) throw new Error('model list rejected');
  #|     const listing = await models.json();
  #|     if (!Array.isArray(listing.data) || !listing.data.some(item => item.id === model)) throw new Error('model not listed');
  #|     const response = await fetch(new URL('/trial/v1/chat/completions', location.origin), {
  #|       method: 'POST', credentials: 'omit', redirect: 'error', cache: 'no-store', signal: controller.signal,
  #|       headers: {'Authorization': 'Bearer ' + secret, 'Content-Type': 'application/json'},
  #|       body: JSON.stringify({model, messages:[{role:'user',content:'请用一句话介绍你能如何帮助创业团队。'}], max_tokens:512, stream:false})
  #|     });
  #|     status = response.status;
  #|     if (!response.ok) throw new Error('request rejected');
  #|     const value = await response.json();
  #|     const content = value.choices?.[0]?.message?.content;
  #|     const safeCount = x => Number.isSafeInteger(x) && x >= 0 && x <= 100000000 ? x : 0;
  #|     const clean = typeof content === 'string' ? content.split(secret).join('[redacted]').slice(0,2000) : '';
  #|     if (!clean.trim()) throw new Error('empty completion');
  #|     const streamed = await fetch(new URL('/trial/v1/chat/completions', location.origin), {
  #|       method:'POST', credentials:'omit', redirect:'error', cache:'no-store', signal:controller.signal,
  #|       headers:{'Authorization':'Bearer ' + secret, 'Content-Type':'application/json'},
  #|       body:JSON.stringify({model, messages:[{role:'user',content:'请用一句话介绍你能如何帮助创业团队。'}], max_tokens:512, stream:true, stream_options:{include_usage:true}})
  #|     });
  #|     status = streamed.status;
  #|     if (!streamed.ok || !streamed.headers.get('content-type')?.includes('text/event-stream')) throw new Error('stream rejected');
  #|     const reader = streamed.body.getReader();
  #|     const decoder = new TextDecoder();
  #|     let pending = '', streamedText = '', done = false, streamUsage = null;
  #|     while (true) {
  #|       const part = await reader.read();
  #|       pending += decoder.decode(part.value || new Uint8Array(), {stream:!part.done});
  #|       const lines = pending.split('\n'); pending = lines.pop();
  #|       for (const line of lines) {
  #|         if (!line.startsWith('data:')) continue;
  #|         const data = line.slice(5).trim();
  #|         if (data === '[DONE]') { done = true; continue; }
  #|         if (!data) continue;
  #|         const chunk = JSON.parse(data);
  #|         if (chunk.error) throw new Error('stream error');
  #|         const text = chunk.choices?.[0]?.delta?.content;
  #|         if (typeof text === 'string') streamedText += text;
  #|         if (chunk.usage) streamUsage = chunk.usage;
  #|       }
  #|       if (part.done) break;
  #|     }
  #|     if (!done || !streamedText.trim()) throw new Error('incomplete stream');
  #|     return JSON.stringify({ok:true, status, elapsed_ms:Math.round(performance.now()-started), input_tokens:safeCount(value.usage?.prompt_tokens)+safeCount(streamUsage?.prompt_tokens), output_tokens:safeCount(value.usage?.completion_tokens)+safeCount(streamUsage?.completion_tokens), content:clean});
  #|   } catch (_) {
  #|     return JSON.stringify({ok:false,status,elapsed_ms:Math.round(performance.now()-started),input_tokens:0,output_tokens:0,content:''});
  #|   } finally { clearTimeout(timer); }
  #| }

///|
fn trial_api_test_summary(
  result : TrialApiTestResult,
  locale : @i18n.Locale,
) -> Result[String, String] {
  if !result.ok || result.content.trim() == "" {
    return Err(
      portal_copy(
        locale,
        "API test failed (HTTP \{result.status}). \{trial_api_error_hint(result.status, locale)} No credentials are included.",
        "API 测试未通过（HTTP \{result.status}）。\{trial_api_error_hint(result.status, locale)} 错误信息不包含密钥。",
      ),
    )
  }
  Ok(
    portal_copy(
      locale,
      "API test passed · model list, chat and SSE stream completed · \{result.elapsed_ms} ms · input \{result.input_tokens} / output \{result.output_tokens} tokens. Reply: \{result.content}",
      "API 测试通过 · 模型列表、普通问答、流式问答均成功 · \{result.elapsed_ms} 毫秒 · 输入 \{result.input_tokens} / 输出 \{result.output_tokens} tokens。回复：\{result.content}",
    ),
  )
}

///|
fn trial_api_error_hint(status : Int32, locale : @i18n.Locale) -> String {
  match status {
    401 =>
      portal_copy(
        locale, "Credential authentication failed; refresh the key list and retry, then contact support if it persists.",
        "密钥鉴权失败；刷新密钥列表后重试，若仍失败请联系平台管理员。",
      )
    403 =>
      portal_copy(
        locale, "The trial or gateway did not authorize this request; contact support to check the binding.",
        "试用授权或网关拒绝请求；请联系平台管理员检查绑定。",
      )
    429 =>
      portal_copy(
        locale, "The service is busy or the account budget is exhausted; retry later.",
        "服务繁忙或账号额度不足，请稍后重试。",
      )
    0 =>
      portal_copy(
        locale, "Network timeout; check connectivity and retry.", "网络连接超时，请检查连接后重试。",
      )
    _ =>
      portal_copy(
        locale, "The model service did not complete a reply; retry or contact support.",
        "模型服务未完成回复，请重试或联系平台管理员。",
      )
  }
}

///|
fn saved_trial_api_test_command(
  model : AppModel,
  key_id : String,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  guard !model.demo_mode &&
    !model.portal.loading &&
    model.portal.trial is Some(trial) &&
    trial.api_key_id == Some(key_id) &&
    trial.revoked_unix_ms is None &&
    trial.expires_unix_ms > current_unix_ms() &&
    trial.allowed_models is [model_alias] else {
    return (model, @rabbita.none)
  }
  let next = {
    ..model,
    portal: model.portal.update(TestSavedTrialApiKey(key_id)),
  }
  let command = @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    let result = try {
      let reply = request(
        "POST",
        model.endpoint,
        "/v1/portal/self/api-keys/" + key_id + ":secret",
        model.token,
        model.subject_ref,
        body="{}",
      )
      let key : SavedApiKeySecret = @json.from_json(@json.parse(reply))
      guard key.key_id == key_id &&
        key.secret.has_prefix("lnx_") &&
        key.secret.length() == 68 else {
        raise Failure("invalid saved key")
      }
      let value = trial_api_test_promise(key.secret, model_alias).wait()
      let text : String = value.cast()
      trial_api_test_summary(
        @json.from_json(@json.parse(text)),
        model.portal.locale,
      )
    } catch {
      _ =>
        Err(
          portal_copy(
            model.portal.locale,
            "Could not test this saved key. Refresh and retry.",
            "无法测试此密钥，请刷新后重试。",
          ),
        )
    }
    TrialApiTested(model.session_generation, result)
  })
  (next, command)
}

///|
fn trial_api_test_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  guard !model.demo_mode &&
    !model.portal.loading &&
    model.portal.one_time_api_key_secret is Some(key) &&
    key.allowed_models is [model_alias] &&
    model.portal.trial is Some(trial) &&
    model.portal.membership is Some(membership) &&
    trial.organization_id == membership.organization_id &&
    trial.tenant_ref == key.tenant_ref &&
    trial.revoked_unix_ms is None &&
    trial.expires_unix_ms > current_unix_ms() &&
    trial.allowed_models.contains(model_alias) else {
    return (model, @rabbita.none)
  }
  let next = { ..model, portal: model.portal.update(TestPersonalTrialApiKey), }
  let command = @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    let result = try {
      let value = trial_api_test_promise(key.secret, model_alias).wait()
      let text : String = value.cast()
      trial_api_test_summary(
        @json.from_json(@json.parse(text)),
        model.portal.locale,
      )
    } catch {
      _ =>
        Err(
          portal_copy(
            model.portal.locale,
            "Could not complete the API test. Please retry.",
            "无法完成 API 测试，请重试。",
          ),
        )
    }
    TrialApiTested(model.session_generation, result)
  })
  (next, command)
}
