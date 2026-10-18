# 用户可停止的运行服务

个人 MoonDesk / 受管 WebIDE 的入口在 `/user` 的 PaaS 页面。「管理／停止我的 WebIDE」
打开其账户绑定网关的 `/workspace-control`。只有已经兑换一次性 handoff、持有该网关
会话且当前授权仍有效的浏览器能确认停止。网关调用 `WorkspaceHost::stop` 将**这个
账户的工作负载**缩到零并清除该工作负载的全部网关会话；PVC 和保存文件不删除。重新
打开需要从 `/user` 再领一次 handoff。其他用户工作区及企业模型不会被关掉。

平台托管的 MaaS / PaaS / IaaS 交付仍使用 `/v1/portal/self/deliveries/{id}:stop`；
企业共享 `ModelApi` 允许创建者或企业管理员停止，个人工作区仅本人停止。界面展示
Stopping、Stopped 和失败状态，不把请求受理等同于资源已释放。

`glm-5.3.flash` 的双机外部实例尚不在上述交付状态机内。
`cmd/glm-control` 在管理节点运行，只接受固定实例的 status/start/stop。
旧 Docker 后端以固定账号
通过 SSH 检查 `.178` 的 `glm53-exl3-head` 和 `.179` 的 `glm53-exl3-worker` 的完整
容器 ID、名称和镜像标识；停止时只使用通过检查的 ID，先 worker 后 head，并再次
检查两者。它不接受来自浏览器的容器名、主机地址或任意命令，也不删除模型文件、
卷或 NFS 容器。返回 Running、Stopped、Partial 或 Unavailable。controller 仅以
`lunanexa-glm-control` Secret 的独立令牌调用内网 `192.0.2.175:5907`，网络策略只
开放该目标端口。公网 `/user` 的 MaaS 页显示真实状态；只有该企业的管理员能确认
停止或重新启动，普通成员只读。启动仅针对两台机器上经镜像与完整容器 ID 校验的
既有 GLM 容器，先检查两台机器均无 GPU 计算进程，再启动 worker 和 head；如有其他
任务或任一容器仍在运行，启动会失败关闭。启动后“容器运行”不等于“推理就绪”，仍须
通过模型健康与别名检查。停止后模型健康检查失败，个人 WebIDE 的模型访问随之失效。

新的 LunaFlux 后端使用 `LUNANEXA_GLM_RUNTIME=systemd-user`，控制配置中固定的
两台 Spark 用户单元。启动先检查两端 GPU 空闲、各有至少 16 GiB 主机可用内存，
再启动 peer 和 coordinator；停止先 coordinator 后 peer，并核验资源释放。
运行中观察两端状态、每端 100 GiB GPU 上限和 16 GiB 主机余量；单端失败或
超限时只停这对单元。单元不独立自动重启，避免一个 TP rank 加入已存活的旧会话。
浏览器不能传入主机地址、单元名或命令。用户入口、企业管理员权限及公开模型别名
不变。实际切换记录与已验证范围见 [GLM_LUNAFLUX_CUTOVER.md](GLM_LUNAFLUX_CUTOVER.md)。

这仍是精确外部实例的适配，不伪装为已实现双机标准交付状态机。将来标准 `ModelApi`
交付接管这对单元时，才统一其停止/恢复生命周期；当前不得自动恢复旧 EXL3 容器。

MaaS 首先展示当前企业共享服务的公网连接信息：当前站点的 `/user/v1` 为 OpenAI
兼容 API base URL，模型名使用 LunaNexa 的公开别名，而非上游文件路径或容器名。
上下文长度只取健康检查通过、批准模型匹配后的 `/v1/models` 中该精确模型的
`max_model_len` 正整数；缺失、异常或服务未就绪时显示 `—`。不把其他模型的示例
上下文或令牌作为默认配置。API 地址和模型名旁提供带可访问名称的复制图标。
创建模型专属密钥在 MaaS 内完成，默认包含 ModelList 和 Inference 范围，绑定所选
公开别名；新密钥只显示一次，默认折叠，可复制或主动展开，关闭后从浏览器状态清除。
