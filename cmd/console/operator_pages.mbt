///|
priv struct OperatorPageRead {
  kind : @ui.OperatorList
  query : @operator_read.PageQuery
  generation : Int64
  value : @operator_read.ReadPage
}

///|
priv struct WorkspacePersonChoice {
  user_id : String
  subject_ref : String
} derive(FromJson)

///|
priv struct OperatorAccessContext {
  people : Array[@ui.AccountChoice]
  workspace_people : Array[WorkspacePersonChoice]
  leases : Array[@workspace.WorkspaceLease]
} derive(FromJson)

///|
priv struct OperatorWorkspaceRow {
  user : @workspace.WorkspaceUser
  grant_count : Int32
} derive(FromJson)

///|
fn operator_page_query(
  state : @ui.ConsoleState,
  kind : @ui.OperatorList,
) -> @operator_read.PageQuery {
  {
    list: kind.read_key(),
    query: state.list_pages.get(kind).map_or("", page => page.query),
    account_id: if kind == AccessRecords {
      state.access_record_account
    } else {
      ""
    },
    cursor: state.remote_list_pages.get(kind).map_or("", page => page.cursor),
  }
}

///|
/// Search is debounced and superseded work aborted. Credentials and search
/// terms stay in headers/body, never the URL or a persistent browser cache.
extern "js" fn operator_page_promise(
  url : String,
  token : String,
  body : String,
  key : String,
  delay : Int32,
) -> @js.Promise =
  #| async (url, token, body, key, delay) => {
  #|   const pending = globalThis.__lunanexaListReads ??= new Map();
  #|   pending.get(key)?.abort();
  #|   const controller = new AbortController();
  #|   pending.set(key, controller);
  #|   try {
  #|     if (delay) await new Promise((resolve, reject) => {
  #|       const timer = setTimeout(resolve, delay);
  #|       controller.signal.addEventListener('abort', () => {
  #|         clearTimeout(timer); reject(new Error('Superseded list read'));
  #|       }, {once:true});
  #|     });
  #|     const fetchPage = async payload => fetch(url, {
  #|       method:'POST', credentials:'same-origin', cache:'no-store', redirect:'error',
  #|       headers:{Accept:'application/json', 'Content-Type':'application/json', Authorization:`Bearer ${token}`},
  #|       body:payload, signal:controller.signal
  #|     });
  #|     let response = await fetchPage(body);
  #|     if (response.status === 409 && JSON.parse(body).cursor) {
  #|       response = await fetchPage(JSON.stringify({...JSON.parse(body), cursor:''}));
  #|     }
  #|     if (!response.ok) throw new Error(`HTTP ${response.status}`);
  #|     return await response.text();
  #|   } finally {
  #|     if (pending.get(key) === controller) pending.delete(key);
  #|   }
  #| }

///|
async fn load_operator_page(
  endpoint : String,
  token : String,
  state : @ui.ConsoleState,
  kind : @ui.OperatorList,
  delay~ : Int32 = 0,
) -> OperatorPageRead {
  let query = operator_page_query(state, kind)
  let base = endpoint.trim_end(chars="/").to_owned()
  let raw : String = operator_page_promise(
      "\{base}/v1/operator/list-page",
      token,
      Json(query).stringify(),
      kind.read_key(),
      delay,
    )
    .wait()
    .cast()
  {
    kind,
    query,
    generation: state.remote_list_pages
    .get(kind)
    .map_or(0L, page => page.generation),
    value: @json.from_json(parse_console_json(raw)),
  }
}

///|
extern "js" fn operator_pages_prefetch(
  url : String,
  token : String,
  bodies : FixedArray[String],
  keys : FixedArray[String],
) -> @js.Promise =
  #| async (url, token, bodies, keys) => JSON.stringify(await Promise.all(bodies.map(async body => {
  #|   const response = await fetch(url, {method:'POST', credentials:'same-origin', cache:'no-store', redirect:'error',
  #|     headers:{Accept:'application/json', 'Content-Type':'application/json', Authorization:`Bearer ${token}`}, body});
  #|   if (!response.ok) throw new Error(`HTTP ${response.status}`);
  #|   return await response.text();
  #| })))

///|
async fn load_operator_pages(
  endpoint : String,
  token : String,
  state : @ui.ConsoleState,
  kinds : Array[@ui.OperatorList],
) -> Array[OperatorPageRead] {
  // A group refresh starts at the first page if its dataset changed. Query and
  // person selection remain intact; individual paging also retries stale cursors.
  let queries = kinds.map(kind => {
    ..operator_page_query(state, kind),
    cursor: "",
  })
  let base = endpoint.trim_end(chars="/").to_owned()
  let raw : String = operator_pages_prefetch(
      "\{base}/v1/operator/list-page",
      token,
      FixedArray::from_array(queries.map(query => Json(query).stringify())),
      FixedArray::from_array(kinds.map(kind => kind.read_key())),
    )
    .wait()
    .cast()
  let results : Array[String] = @json.from_json(@json.parse(raw))
  kinds.mapi((index, kind) => {
    kind,
    query: queries[index],
    generation: state.remote_list_pages
    .get(kind)
    .map_or(0L, page => page.generation),
    value: @json.from_json(parse_console_json(results[index])),
  })
}

///|
fn operator_page_matches(
  state : @ui.ConsoleState,
  read : OperatorPageRead,
) -> Bool {
  state.remote_list_pages.get(read.kind).map_or(0L, page => page.generation) ==
  read.generation &&
  state.list_pages.get(read.kind).map_or("", page => page.query) ==
  read.query.query &&
  (
    read.kind != AccessRecords ||
    state.access_record_account == read.query.account_id
  )
}

///|
fn merge_operator_page(
  current : @ui.ConsoleState,
  read : OperatorPageRead,
) -> @ui.ConsoleState {
  if !operator_page_matches(current, read) {
    return current
  }
  let remote = current.remote_list_pages.copy()
  let page = read.value
  // A changed data set resets the server to page one. Preserve its actual
  // cursor rather than the expired request cursor for the next refresh.
  remote[read.kind] = {
    total: page.total,
    page: page.page,
    cursor: if page.page == 0 {
      ""
    } else {
      read.query.cursor
    },
    previous_cursor: page.previous_cursor,
    next_cursor: page.next_cursor,
    generation: read.generation,
    loading: false,
    failed: false,
  }
  let positions = current.list_pages.copy()
  positions[read.kind] = { query: read.query.query, page: page.page, }
  let next = { ..current, remote_list_pages: remote, list_pages: positions, }
  try {
    match read.kind {
      Accounts =>
        { ..next, accounts: page.items.map(item => @json.from_json(item)), }
      WorkspaceProfiles =>
        {
          ..next,
          users: page.items.map(item => {
            let row : OperatorWorkspaceRow = @json.from_json(item)
            {
              user_id: row.user.user_id,
              display_name: row.user.display_name,
              email: row.user.email,
              state: row.user.state,
              last_active: row.user.last_active_unix_ms
              .map(timestamp => format_unix_ms(timestamp, "Unavailable"))
              .unwrap_or("Never"),
              grant_count: row.grant_count,
            }
          }),
        }
      AccessGrants =>
        {
          ..next,
          access_grants: page.items.map(item => {
            let grant : @workspace.WorkspaceAccessGrant = @json.from_json(item)
            {
              grant_id: grant.grant_id,
              user_id: grant.user_id,
              role: grant.access,
              scope: grant.tenant_ref,
              state: grant.state,
              expires_at: format_unix_ms(grant.expires_unix_ms, "Unavailable"),
            }
          }),
        }
      AccessRecords =>
        {
          ..next,
          access_packages: page.items.map(item => @json.from_json(item)),
        }
      AuditEvents =>
        {
          ..next,
          audit: page.items
          .rev()
          .map(item => {
            let event : @contracts.AuditEvent = @json.from_json(item)
            {
              actor: event.actor,
              decision: event.action,
              evidence: event.target,
              result: event.result,
              receipt: event.correlation_receipt,
            }
          }),
        }
      RequestReceipts =>
        {
          ..next,
          request_details: page.items
          .rev()
          .map(item => {
            let event : @contracts.AuditEvent = @json.from_json(item)
            {
              timestamp_unix_ms: event.timestamp_unix_ms,
              action: event.action,
              model_selector: event.target,
              result: event.result,
              receipt: event.correlation_receipt,
            }
          }),
        }
      ModelRegistry | ServiceCatalog => next
    }
  } catch {
    _ => {
      let metadata = remote[read.kind]
      remote[read.kind] = { ..metadata, failed: true, }
      { ..current, remote_list_pages: remote, }
    }
  }
}

///|
fn schedule_operator_page(
  model : AppModel,
  kind : @ui.OperatorList,
  cursor : String,
  delay : Int32,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  if model.demo_mode ||
    !model.console.operator_authenticated ||
    kind == ModelRegistry ||
    kind == ServiceCatalog {
    return (model, @rabbita.none)
  }
  let pages = model.console.remote_list_pages.copy()
  let previous = pages.get(kind)
  let generation = previous.map_or(0L, page => page.generation) + 1L
  pages[kind] = {
    total: previous.map_or(0, page => page.total),
    page: model.console.list_pages.get(kind).map_or(0, page => page.page),
    cursor,
    previous_cursor: "",
    next_cursor: "",
    generation,
    loading: true,
    failed: false,
  }
  let next = {
    ..model,
    console: { ..model.console, remote_list_pages: pages, },
  }
  let token = if kind == AuditEvents || kind == RequestReceipts {
    next.audit_credential
  } else {
    next.credential
  }
  let endpoint = next.endpoint
  let state = next.console
  let command = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try
      OperatorPageLoaded(
        token,
        load_operator_page(endpoint, token, state, kind, delay~),
      )
    catch {
      error =>
        OperatorPageFailed(token, kind, generation, http_status_is(error, 401))
    } noraise {
      value => value
    }
  })
  (next, command)
}
