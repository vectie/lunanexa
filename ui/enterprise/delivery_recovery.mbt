///|
fn delivery_retry_primary(operation : DeliveryView) -> Bool {
  operation.can_manage &&
  operation.stage == "Failed" &&
  operation.failure_code == Some("ModelReadinessTimeout")
}

///|
fn delivery_failure_guidance(
  operation : DeliveryView,
  locale : @i18n.Locale,
) -> String {
  match operation.failure_code {
    Some("ModelReadinessTimeout") if operation.can_manage =>
      copy(
        locale, "The service did not become ready in time. Retry this delivery; if it fails again, contact the platform operator.",
        "服务未在规定时间就绪，可重试本次交付；再次失败请联系平台管理员。",
      )
    Some("ModelReadinessTimeout") =>
      copy(
        locale, "The service did not become ready in time. Ask your company administrator to retry this delivery.",
        "服务未在规定时间就绪，请企业管理员重试本次交付。",
      )
    Some("ModelPreparationFailed") =>
      copy(
        locale, "Model files could not be prepared. Ask the platform operator to check the model files and storage.",
        "模型文件准备失败，请平台管理员检查模型文件与存储。",
      )
    Some("ModelDeploymentBlocked") =>
      copy(
        locale, "Deployment is blocked. Ask the platform operator to check the published template and resource allocation.",
        "部署被阻止，请平台管理员检查已发布模板与资源归属。",
      )
    _ =>
      copy(
        locale, "The service needs operator attention. Copy the delivery reference for the platform operator.",
        "服务需要平台管理员处理，请复制交付记录供其排查。",
      )
  }
}

///|
fn delivery_failure_actions(
  panel : DeliveryPanel,
  operation : DeliveryView,
  locale : @i18n.Locale,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  if operation.stage != "Failed" {
    return @html.nothing
  }
  let retry = @html.button(
    type_="button",
    class="primary-button",
    disabled=panel.loading,
    on_click=command(emit, Delivery(Retry(operation.operation_id))),
    copy(locale, "Retry this delivery", "重试本次交付"),
  )
  @html.fragment([
    @html.button(
      type_="button",
      class="quiet-button",
      on_click=command(
        emit,
        CopyDetail(
          "Delivery: \{operation.operation_id}\nCode: " +
          operation.failure_code.unwrap_or("Unknown"),
        ),
      ),
      copy(locale, "Copy failure reference", "复制故障信息"),
    ),
    if delivery_retry_primary(operation) {
      retry
    } else if operation.can_manage {
      @controls.advanced(
        copy(locale, "Retry after repair", "修复后重试"),
        [retry],
      )
    } else {
      @html.nothing
    },
  ])
}
