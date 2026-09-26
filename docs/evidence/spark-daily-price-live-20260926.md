# DGX Spark 线上日价发布核对（2026-09-26，北京时间）

本记录更新此前按秒计价的现场证据；旧报告中的 ¥1,728 是当时生成、现已过期的报价，不是当前价，也不是订单。旧记录保留为历史事实。

## 已发布

- `main` 中新增按计价单位报价，Spark 商品统一按整天计价；过期或改价前的旧报价不能创建订单。
- 先滚动 `lunanexa-control`，再通过受鉴权的 operator API 逐条更新 `offer-dgx-spark-01`、`offer-dgx-spark-02`、`offer-dgx-spark-03`。迁移前机器订单为 0；迁移脚本检查旧价和代数，写后再次读取核对。
- PostgreSQL `machine_commerce` 快照中的三条商品均为 `unit_price.minor_units=4900`、`price_unit_seconds=86400`、`billing_quantum_seconds=86400`、`minimum_duration_seconds=86400`、`generation=2`。即每台机器每完整一天 ¥49。
- 企业门户已滚动到新的 Web 镜像。公网 `/user/`、`/mana/`、`/docs/` 和 ComfyUI `:5005/` 均返回 HTTP 200。

## 验证边界

- 浏览器登录现有 CeShi 测试账户并选企业后，IaaS 路径显示“当前无可用算力”；这与商品计价无关，但意味着本轮无法从 UI 创建新的 ¥49 报价。没有为了测价格停止占用 GPU 的业务或伪造库存。
- 线上尚无经审核发布的 `machine-self-service` 条款模板。现存《承诺函》是需要签章、管理侧审批的另一条路径，不能改名作为“点击接受”的机器自助条款；因此本轮没有记录任何线上条款接受、订单或付款。
- 承诺函现有周/月档位仍为 ¥322/¥1290；它们没有被本次“机器自助 SKU ¥49/天”迁移改写。

## 回退与版本

- 控制器镜像：`sha256:23b656a601917b2b64653631eca595d7e20fb5b967796ca6dc5dcfbd69023579`；升级前 `sha256:c4f151845e414a79226cff1f4c9fe54d1e5fa8f71e158ba9272fa52491a53587`。
- 企业 Web 镜像：`sha256:933d551cfe906b754cb8920602f005c218f196654acf78f9f37342f00e3d77fa`；升级前 `sha256:64a7cfad690faacbd82c64e233847beea3d137c94b07c791c2371d7a21c98223`。
- 代码提交：`e0ed871`、`b372f7f`、`19067b0`。源码与迁移程序均已推送 GitHub、GitLab `main`。
