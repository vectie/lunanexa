# fb2c 一日技术测试授权（2026-09-28）

## 实际完成

- 用户在当前任务中确认：仅为 CeShi 测试账户开通 24 小时 Developer／工作区权限，机器须通过准入检查后才分配；不记录合同签署或付款完成。
- 公网管理端 `/mana/` 的“策略 → 类型化运维操作”提交 `grant-fb2c-technical-1d-20260928`，页面反馈 `grant-access 已完成`；“用户与访问权限”显示该授权于 **2026-09-29 12:06:50 北京时间**到期。
- 同一界面创建 `lease-fb2c-technical-1d-20260928`，再在“租约”页点击“激活”；页面反馈“工作区租约…已激活”，列表显示文本生成 1 路并发、**2026-09-28 12:06:50 至 2026-09-29 12:06:50 北京时间**有效。
- 公网 `/user/` 使用 CeShi 测试账户登录成功；企业组织可以看到 IaaS、PaaS、MaaS 入口。WebIDE 页当前提示“请先部署并验证至少一个可调用模型”，打开按钮禁用；这不是 WebIDE 已可用的证据。
- 旧独占租约 `fb2c-exclusive-20260927` 已由宿主清理助手生成实际撤销与清理回执，管理端显示“已清理 / 已完成”，代际 7；旧 fb2c 订单显示“已到期，需重新下单”。

## 本轮软件与生产更新

- 修正独占租约清理授权阶段：在 `RevokingAccess` 时允许控制器签发 sanitize 授权；此前自动回收在此阶段无法推进。
- 为 Kubernetes 上的独占租约代理提供独立部署与 host-root helper 转接，仅在 `.178` 节点部署；普通受管节点代理保持不变。
- 修正重复远程指令覆盖本地已签清理回执的问题；发送待确认回执后才重新应用远程指令，并记录观察请求的传输失败。
- 管理控制器镜像 `docker.io/library/lunanexa-control:20260928-sanitize-r1`、`.178` 专用代理镜像 `docker.io/library/lunanexa-node:20260928-lease-r4` 均已滚动为 `1/1 Ready`。`.176/.177` 试用服务未更新。

## 仍未完成，不能记为交付

- 没有为新的一日权限创建或下发 `.178` 独占机器租约。用户端“我的机器”仍为 0 条。
- 用户侧没有 SSH 公钥录入及凭据发放到宿主 `/run/lunanexa/lease-credentials/` 的闭环；没有凭据文件时，宿主 helper 会拒绝 provision。
- `.178` 宿主没有 Podman，而当前裸机租约清理器依赖 Podman 查询、停止和删除租户 rootless 容器。需要接入受管 Kubernetes/containerd 的可信清理证据，或明确提供独立且可验收的租户容器运行时。
- 新代理的“自动提交回执 → 控制器状态推进”尚未以新租约端到端复测。旧租约清理中，最后两份真实宿主签名回执曾由运维手动送达控制器；不能据此宣称自动回收全程已通过。
- 本次是**未签署、未付款、非商业技术豁免**；没有把承诺函订单或商业履约状态改为完成。

## 本地验证

- `moon test nodelease --target native --deny-warn`：23/23 通过。
- `moon test cmd/lease-helper-client --target native --deny-warn`：1/1 通过。
- `moon test cmd/node --target native --deny-warn`：3/3 通过。
- `moon test cmd/loopback-proxy --target native --deny-warn`：4/4 通过。
- `moon check cmd/node --target native --deny-warn`、`moon info && moon fmt`、`git diff --check` 通过。
