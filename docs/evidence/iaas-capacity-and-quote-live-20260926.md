# DGX Spark IaaS 库存与报价现场复测（2026-09-26，北京时间）

本轮把“当前无可用算力”拆解为节点心跳标签与实际内存占用，而非价格或前端故障。现场仅停止企业池 `.178/.179` 上的 GLM 双机 Docker 容器，未删除容器、镜像或模型，也未操作 `.176/.177` 的 MiniMax H3/ComfyUI 试用。

## 操作与双端结果

1. 管理侧 `/v1/nodes` 显示 `.178` 的 Kubernetes 节点和 inventory ConfigMap 均有 `lunanexa.io/usage-pool=enterprise-dedicated`，但旧节点代理送到控制器的心跳缺少该标签。`.179` 心跳已有标签。两台节点的 `host_memory_available_mib` 均仅约 8–10 GiB；现场进程与 Docker 容器核对为 `glm53-exl3-head` 和 `glm53-exl3-worker` 占用。
2. 分别停止上述两个 GLM 容器后，控制器收到两台节点约 120000 MiB（约 118 GiB）可用统一内存。滚动 `.178` 节点代理以读取已挂载的 inventory，再升级为与 `.179` 相同的 `node-iaas` 热更新镜像 `sha256:d04afdb7cb1c2d6b298027f26db8cf4710815caf0f04c78b14c35de7c4519e2e`。两台代理 Deployment 均为 `1/1`，新心跳均为 Active 且带企业池标签。
3. 公网 `/user` 登录既有 CeShi 测试账户，选择“企业专属云 WebIDE 验收”→“自助开通”→“租用独占 GPU 算力”。页面出现 `offer-dgx-spark-02`、`offer-dgx-spark-03` 两款可用配置，均显示 **¥49.00 / 天**。
4. 选择 `offer-dgx-spark-03`，填写测试 Linux 用户名、`cn-north-1`、24 小时，点击“查看报价”。服务端返回签名报价 `machine-quote-5849e549-d677-47cc-b0ed-93b238b05ba9`，总额 **CNY 49.00**，有效期至北京时间 2026-09-26 17:13:03。它是报价，不是订单、租约或付款。
5. 报价页明确提示“平台尚未发布经审核的机器条款，下单暂不可用”，「创建订单」为禁用。商业快照有 0 份协议模板、0 份组织协议和 0 条点击接受记录；管理 readiness 的 `commercial_provider_adapter_configured=false`。因此即便发布条款，现有付费订单仍缺支付适配器，不能宣称全链路已开通。

## 边界

- 此次实测没有创建订单、接受法律条款、签署承诺函、付款或分配独占机器。
- 《设备使用承诺函》原文要求企业签字及盖章，并要求管理侧审批和支付后开通；它不是已经审核上线的 `machine-self-service` 点击接受模板。不能用技术手段将一份未签文件记为已签或把测试豁免记为商业付款。
- GLM 双机容器的停止是可逆的，但其间 `:5002/:5003` MoonCode 的 GLM 推理不可用；直接访问网关返回 401 是独立交接认证的正常行为，不等于页面宕机。

## 收尾状态

由于线上自助条款和商业支付适配器均未就绪，报价不能变成商业订单，故没有继续空置两台企业节点。先启动 `.179` 的 `glm53-exl3-worker`，再启动 `.178` 的 `glm53-exl3-head`。等待权重加载完成后，`GET /v1/models` 返回 HTTP 200；关闭思考输出的真实 `POST /v1/chat/completions` 返回 `content=OK`、`finish_reason=stop`。两台节点重新承载 GLM 时，自助机器库存按统一内存安全规则回到不可售，这是预期状态。下次 IaaS 实单窗口必须先安排 GLM 腾挪或停机，并准备经审核的线上条款及真实支付适配器；本轮没有用假接受或假付款绕过它们。
