///|
pub fn registered_access_ready(state : ConsoleState) -> Bool {
  state.operator_authenticated &&
  !state.loading &&
  state.accounts.any(account => {
    account.account_id == state.registered_access_account &&
    account.state == Active &&
    account.roles.contains(EnterpriseUser)
  }) &&
  state.access_organizations.any(org => {
    org.organization_id == state.access_package_draft.organization_id
  })
}

///|
fn registered_access_form(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.details(
    class="access-package-panel ln-advanced",
    open=state.registered_access_account != "" ||
      state.access_packages.is_empty(),
    [
      @html.summary(
        localized(
          state.locale,
          "Review and open access",
          "审核并开通访问",
        ),
      ),
      @html.div(class="access-package-form-grid", [
        @html.div(class="field-group", [
          @html.label(
            for_="registered-access-person",
            localized(state.locale, "Registered person", "已注册人员"),
          ),
          @html.select(
            id="registered-access-person",
            disabled=state.loading,
            on_change=text_command(emit, value => {
              RegisteredAccessAccountChanged(value)
            }),
            [
              @html.option(
                value="",
                selected=state.registered_access_account == "",
                localized(state.locale, "Choose a person", "选择人员"),
              ),
              ..[
                for account in state.accounts if account.state == Active &&
                account.roles.contains(EnterpriseUser) => {
                  @html.option(
                    value=account.account_id,
                    selected=account.account_id ==
                      state.registered_access_account,
                    "\{account.display_name} · \{account.email}",
                  )
                }
              ],
            ],
          ),
        ]),
        @html.div(class="field-group", [
          @html.label(
            for_="registered-access-organization",
            localized(state.locale, "Approved organization", "已审核组织"),
          ),
          @html.select(
            id="registered-access-organization",
            disabled=state.loading,
            on_change=text_command(emit, value => {
              AccessPackageOrganizationChanged(value)
            }),
            [
              @html.option(
                value="",
                selected=state.access_package_draft.organization_id == "",
                localized(
                  state.locale,
                  "Choose an organization",
                  "选择组织",
                ),
              ),
              ..[
                for organization in state.access_organizations => {
                  @html.option(
                    value=organization.organization_id,
                    selected=organization.organization_id ==
                      state.access_package_draft.organization_id,
                    organization.display_name,
                  )
                }
              ],
            ],
          ),
        ]),
        @html.div(class="field-group", [
          @html.label(
            for_="registered-access-duration",
            localized(state.locale, "Access duration", "访问期限"),
          ),
          @html.select(
            id="registered-access-duration",
            disabled=state.loading,
            on_change=text_command(emit, value => {
              AccessPackageLifetimeChanged(
                @string.parse_int(value) catch {
                  _ => 30
                },
              )
            }),
            [
              for days in [0, 7, 30, 90] => {
                @html.option(
                  value=days.to_string(),
                  selected=days == state.access_package_draft.lifetime_days,
                  if days == 0 {
                    localized(state.locale, "1 hour test", "1 小时测试")
                  } else {
                    localized(state.locale, "\{days} days", "\{days} 天")
                  },
                )
              }
            ],
          ),
        ]),
      ]),
      @html.p(
        localized(
          state.locale,
          "Enterprise user + Developer · Text generation · 2 concurrent requests · 100 requests/hour",
          "企业用户 + 开发者 · 文本生成 · 2 个并发请求 · 每小时 100 个请求",
        ),
      ),
      if state.access_organizations.is_empty() {
        @html.p(
          class="notice is-warning",
          localized(
            state.locale,
            "No approved organization with a complete tenant mapping is available. Complete company review first.",
            "暂无组织具备完整租户归属，请先完成企业审核或补齐组织归属。",
          ),
        )
      } else {
        @html.nothing
      },
      @html.button(
        type_="button",
        class="primary-button",
        disabled=!registered_access_ready(state),
        on_click=command(emit, SubmitRegisteredAccess),
        localized(
          state.locale,
          "Approve and open access",
          "审核并开通访问",
        ),
      ),
    ],
  )
}

///|
fn registered_access_records(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let people : Map[String, String] = Map([])
  for item in state.access_packages {
    people[item.account_id] = "\{item.display_name} · \{item.email}"
  }
  for account in state.accounts {
    people[account.account_id] = "\{account.display_name} · \{account.email}"
  }
  let records = paged_rows(
    state,
    AccessRecords,
    state.access_packages.filter(item => {
      item.account_id == state.access_record_account &&
      Some((item.account_id, item.organization_id)) !=
      state.access_package_context
    }),
    item => {
      item.organization_id +
      " " +
      item.state +
      " " +
      state.access_organizations
      .iter()
      .find_first(org => org.organization_id == item.organization_id)
      .map_or("", org => org.display_name)
    },
  )
  @html.section(class="access-package-panel field-group", [
    @html.label(
      for_="access-record-person",
      localized(state.locale, "View a person's access", "查看人员权限"),
    ),
    @html.select(
      id="access-record-person",
      on_change=text_command(emit, value => AccessRecordAccountChanged(value)),
      [
        @html.option(
          value="",
          selected=state.access_record_account == "",
          localized(state.locale, "Choose a person", "选择人员"),
        ),
        ..people
        .to_array()
        .map(person => {
          @html.option(
            value=person.0,
            selected=state.access_record_account == person.0,
            person.1,
          )
        }),
      ],
    ),
    if state.access_record_account != "" {
      list_controls(state, AccessRecords, records, emit)
    } else {
      @html.nothing
    },
    @html.div(
      class="access-package-list",
      [
        for item in records.rows => access_package_card(state, item, emit)
      ],
    ),
  ])
}
