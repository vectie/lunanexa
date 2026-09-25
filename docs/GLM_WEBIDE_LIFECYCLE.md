# 用户可停止的运行服务

个人 MoonDesk / 受管 WebIDE 的入口在 `/user` 的 PaaS 页面。「管理／停止我的 WebIDE」
打开其账户绑定网关的 `/workspace-control`。只有已经兑换一次性 handoff、持有该网关
会话且当前授权仍有效的浏览器能确认停止。网关调用 `WorkspaceHost::stop` 将**这个
账户的工作负载**缩到零并清除该工作负载的全部网关会话；PVC 和保存文件不删除。重新
打开需要从 `/user` 再领一次 handoff。其他用户工作区及企业模型不会被关掉。

平台托管的 MaaS / PaaS / IaaS 交付仍使用 `/v1/portal/self/deliveries/{id}:stop`；
企业共享 `ModelApi` 允许创建者或企业管理员停止，个人工作区仅本人停止。界面展示
Stopping、Stopped 和失败状态，不把请求受理等同于资源已释放。

当前 `glm-5.3.flash` 是历史遗留的两机宿主 Docker 服务，不在上述交付状态机内。
为这**一个精确实例**增加过渡控制：`cmd/glm-control` 在管理节点运行，以固定账号
通过 SSH 检查 `.178` 的 `glm53-exl3-head` 和 `.179` 的 `glm53-exl3-worker` 的完整
容器 ID、名称和镜像标识；停止时只使用通过检查的 ID，先 worker 后 head，并再次
检查两者。它不接受来自浏览器的容器名、主机地址或任意命令，也不删除模型文件、
卷或 NFS 容器。返回 Running、Stopped、Partial 或 Unavailable。controller 仅以
`lunanexa-glm-control` Secret 的独立令牌调用内网 `192.168.2.175:5907`，网络策略只
开放该目标端口。公网 `/user` 的 MaaS 页显示真实状态；只有该企业的管理员能确认
停止或重新启动，普通成员只读。启动仅针对两台机器上经镜像与完整容器 ID 校验的
既有 GLM 容器，先检查两台机器均无 GPU 计算进程，再启动 worker 和 head；如有其他
任务或任一容器仍在运行，启动会失败关闭。启动后“容器运行”不等于“推理就绪”，仍须
通过模型健康与别名检查。停止后模型健康检查失败，个人 WebIDE 的模型访问随之失效。

这只是旧服务过渡适配，不应作为新模型交付模板。新 GLM 必须由 LunaNexa 的双机
受管部署创建，进而统一使用标准 `ModelApi` 交付的停止/恢复生命周期。
