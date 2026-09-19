# 真实集群修复记录 — 2026-09-18/19

本记录覆盖管理节点 `192.168.2.175`（k3s control-plane，主机名 `ubuntu`）与四台
DGX Spark（`.176`–`.179`，ARM64，各 1× GB10）上的问题定位与修复。所有结论都来自
集群实测，命令与产物路径保持原样，便于复现。

修复后的对外入口：

| 用途 | 地址 | 备注 |
|---|---|---|
| 运维控制台 | `http://106.39.18.146:4174/console/` | 免登录，首次加载约 16 秒 |
| ComfyUI | `http://106.39.18.146:5000/`（备用 `:5002`） | 内网同为 `192.168.2.175:5000` |
| 课程手册 | `http://106.39.18.146:4173/` | 静态站 |
| MiniMax-H3 FL2VA | `http://192.168.2.175:4174/h3` | vLLM-Omni API，key 由网关注入 |
| MiniMax-H3 Ref2VA | `http://192.168.2.175:4174/h3r` | 同上 |

---

## 1. 集群管理页没有实时数据

### 1.1 四台 spark 从未注册（节点全部 Pending）

- **症状**：`/v1/nodes` 里只有已下线的 `lunanexa-gpu-180`；控制台 Nodes 页为空。
- **根因**：唯一的节点 agent 是单副本 Deployment，`nodeSelector`、`LUNANEXA_NODE_ID`、
  secret 与 hostPath 全部硬绑定在不可达的 `lunanexa-gpu-180` 上，调度器把它判为 Pending。
- **修复**：删除该 Deployment 与卡死 Pod，`kubectl delete node lunanexa-gpu-180`；随后为
  四台 spark 各自创建独立身份（见 1.2–1.5）。

### 1.2 没有 ARM64 的 node-agent 镜像

- **根因**：内部 registry 中 `moon/lunanexa-node` 全部是 `amd64`，spark 是 `aarch64`。
- **修复**：在 spark `.176` 上原生构建（`~/moon` 工具链、`~/sysroot` 中的 libpq 头/库），
  再用脚本手工组装 scratch 风格 OCI 镜像（二进制 + glibc + `libnvidia-ml` + ca 证书 +
  `/etc/passwd|group|nsswitch.conf`），`ctr -n k8s.io images import` 导入四台节点。
  镜像制作脚本存于 `~/pkg-node-image.sh`。

### 1.3 构建链上的四个坑

- **macOS 打包污染**：tar 带入 `._*` AppleDouble 文件，moon 报
  `Could not read the file because it contains invalid UTF-8 streams`。
  → 传完后 `find <dir> -name '._*' -delete`；本机打包加 `COPYFILE_DISABLE=1`。
- **registry 索引缺失**：spark 无外网，moon 报
  `Failed to resolve registry dependency ... module was not found in the registry`。
  → 从管理机工具链复制 `registry/` 到 spark 的 `~/moon/registry`。
- **私有依赖版本**：`vectie/moonleaf@0.1.15` 不在旧索引里。
  → 在本机执行 `moon update` 下载 0.1.15，再把 `.mooncakes/` 与更新后的
  `registry/index/user/vectie/moonleaf.index` 同步到 spark。
- **C 头文件与库**：`ldd` 显示运行期需要 `libpq.so.5`，但编译期需要
  `libpq-fe.h` → 解包 Ubuntu noble arm64 的 `libpq-dev`/`libpq5` 到 `~/sysroot`，
  通过 `CPATH`/`LIBRARY_PATH`/`LD_LIBRARY_PATH` 提供。

### 1.4 镜像短名解析

- **症状**：Pod `ImagePullBackOff`，事件显示去 `docker.io/library/...` 拉取。
- **根因**：CRI 把 `lunanexa-node:tag` 规范化为 `docker.io/library/lunanexa-node:tag`，
  与导入时的引用名不一致，即使 `imagePullPolicy: IfNotPresent` 也会尝试联网。
- **修复**：`ctr -n k8s.io images tag <ref> docker.io/library/<ref>`（每台节点都做）。

### 1.5 节点身份材料（逐台）

一次性 bootstrap token 由运维签发，**node-token 也必须由运维预先生成**并放进
Secret —— agent 启动时即读取 `LUNANEXA_NODE_TOKEN_PATH`，缺文件直接崩溃：

- Secret 需含 `node-token`、`bootstrap-token-id`、`bootstrap-token` 三个键；
- `inventory.json` 的 `memory_free_mib` 必须是 **数字**（字符串会让 agent 报
  `JsonDecodeError((/accelerators/0/memory_free_mib, Int::from_json: expected number))`）；
- 状态目录需在宿主机预建并 `chown 65532:65532`。

### 1.6 GPU 遥测拿不到：设备与解析两道坎

- **坎一（权限）**：容器内 `nvidia-smi` 报
  `Failed to initialize NVML: Unknown Error`。仅挂 `/dev/nvidia*` 不够，device cgroup
  仍拒绝；改为 privileged（保留 `readOnlyRootFilesystem`），loopback 代理容器维持非特权。
- **坎二（解析）**：GB10 是统一内存，NVML 返回 `[N/A]`（**带方括号**），而
  `node/telemetry_collector.mbt` 只判断 `"N/A"` 且一旦出现就丢弃整条快照，
  于是所有节点只剩 inventory 兜底指标。
  修复：新增 `memory_measured` 标志，两种写法都识别，内存指标回落实测 inventory，
  利用率/温度/功耗仍取驱动读数；同一快照内**所有**行必须一致，混用判为非法。
  见 `node/telemetry_collector.mbt`、`cmd/node/main.mbt`、`node/telemetry_collector_test.mbt`。

### 1.7 Agent 反复报 “reconciliation failed”

- **directive 404**：`GET /v1/nodes/{id}/directive` 在没有指令时返回 404，agent 当作失败。
  → 用 operator API `PUT /v1/nodes/directive` 为四台节点写入 `Active` 指令（generation=1）。
- **证书 401**：控制面把状态从文件迁到 PostgreSQL 后，迁移快照里的证书序列（10）落后于
  agent 持有的序列（11），rotate 校验失败并长期 401。
  → 重新注册：签发新 bootstrap token、更新 Secret、删除
  `/var/lib/lunanexa/node-agent/node-certificate.json`、重启 agent Pod（重建为序列 1）。

---

## 2. 控制面版本落后于前端

- **症状**：控制台调用 `/v1/accounts`、`/v1/catalog/templates` 等返回 404（部署里的控制面
  是旧构建）。
- **修复**：在管理机用 r82 工具链（`~/moon-public/work/r74-identity/tools-r82`）构建
  HEAD 的 `cmd/control`；镜像采用「旧镜像 libs 层 + 新二进制层」的层交换方式重建
  （注意**新二进制层必须在上层**，否则被 libs 层里烤进去的旧二进制覆盖）。

### 2.1 新二进制的运行期依赖

- 宿主机（Ubuntu 20.04，glibc 2.31）产出的二进制需要 `libpthread.so.0`、`libdl.so.2`、
  `libssl.so.1.1`、`libcrypto.so.1.1`，而旧镜像的 libs 来自 bookworm（glibc 2.36、OpenSSL 3）。
- → 打包时带上宿主机 `ldd` 闭包并**额外**补 `libnss_dns.so.2`/`libnss_files.so.2`
  （glibc 运行期 dlopen，ldd 看不到；缺失表现为
  `DatabaseError.ConnectionUnavailable`，因为 DNS 解析失败）。

### 2.2 其他控制面问题

- **imagePullPolicy=Always**：控制面容器强制联网拉 `docker.io`，内网环境必然失败
  → 改为 `IfNotPresent`。
- **空 deployments 快照签名**：旧快照由已轮换的密钥签名，无法验证
  （`DeploymentStoreError.InvalidSnapshot`）→ 该域内容为空，直接删除让控制面自建。
- **状态迁移**：`cmd/control-state-migrate` 把 6 个域（control、model_registry、
  node_enrollment、scheduler、telemetry、deployments）从文件原子迁到 PostgreSQL；
  前置动作是删除目标域里的空快照行；`LUNANEXA_CATALOG_SIGNING_SECRET` 必须取
  Secret 中的 `catalog-signing-secret`（不是 `assignment-signing-secret`）。
- **探针超时导致重启循环**：liveness/readiness 1 秒超时，控制面事件循环偶发 >1 秒阻塞，
  5 小时内重启 14 次 → 放宽为 `timeoutSeconds: 15`、`periodSeconds: 20/30`、
  `failureThreshold: 5`，之后 0 重启。

---

## 3. 控制台卡在登录页（三个叠加原因）

### 3.1 MoonBit `Option` 解码不接受显式 `null`

- **根因**：控制面把没有值的可选字段写成 `null`，而 MoonBit 派生的 `Option` 解码器
  只接受「字段缺失」，遇到 `null` 抛
  `JsonDecodeError((/0/grant_id, String::from_json: expected string))`；
  由于首个这样的字段就抛出，整个首屏加载失败并停留在登录页。
- **修复**：`cmd/console/main.mbt` 新增 `parse_console_json`，解析前递归剔除对象里的
  `null` 成员（`@json.Replacer` + `transform`），并把 34 处响应解析全部改走它。

### 3.2 `user_id` 线上形状不一致

- **根因**：`api/access_onboarding_http.mbt` 的 access package 视图把 `user_id`
  序列化成数组（`["trial-user-…"]`），控制台按单个可选字符串解码。
- **修复**：服务端输出确定字符串（`user.map(v => v.user_id).unwrap_or("")`）。

### 3.3 数据量与串行请求

- **遥测过大**：`/v1/telemetry` 每次返回 1.4 MB / 10000 条样本，WAN 上要 8–11 秒。
  → `admin-settings.json` 的 `retention.telemetry_sample_entries` 由 10000 降到 400
  （约 56 KB），并在网关上对 JSON 开 gzip（**3.3 KB**，0.7 秒）。
- **串行首屏**：加载路径顺序发 20 个请求，WAN 上 RTT 叠加。
  → 新增 `prefetch_get`/`prefetch_console_reads` 并发预取，`request()` 对 GET 消费缓存；
  真实浏览器实测首屏 **40.6 秒 → 16.5 秒**。
- **缺少等待提示**：加载期间仍显示登录页（登录按钮还要求 `lnxs_` 前缀，点不动）。
  → 部署级 open 模式且加载中时渲染 `console_loading_view`。

### 3.4 免登录只匹配一个 origin

- **根因**：open 模式要求 meta 值与页面 origin 完全相等，写死的是 WAN 地址，
  通过内网 IP 或带端口差异访问就不生效。
- **修复**：支持 `lunanexa-operator-open` 内容为 `*`（任意可达 origin），并对
  `/console/` 下发 `Cache-Control: no-store`，避免浏览器复用旧页面。

### 3.5 静态资源 404

- 页面引用根路径 `/assets/...`，而网关只代理 `/console/`
  → nginx 增加 `location /assets/`。

### 3.6 本地无法生成 mbti

- 本机工具链 0.1.20260807 对整模块 `moon check/info` 报 126 个解析期错误
  （仓库既有阻塞，见 `docs/MEDIA_GENERATION.md` 关于 `vectie/moonleaf` 的说明）。
  → 在 spark（0.1.20260915）上跑 `moon info --target native` 验证：0 errors，
  生成的 `ui/pkg.generated.mbti` 含新字段。仓库中的 mbti 仍待该环境回写。

---

## 4. 端口与网络

### 4.1 4173 / 4174 角色错位

- **4173** 当时被改成控制台代理，说明站 Pod 处于 `ErrImageNeverPull`（containerd 内容损坏，
  且 registry 里没有该镜像）。
  → 用层交换重建 docs-static 镜像（nginx 基础层 + docs-site 内容层 + 覆盖 nginx 配置），
  把 `lunanexa-coursebook-public` 重新指回静态站。
- **4174** 无人监听 → 让 hostNetwork 的 nginx（原 `operator-4173-proxy`）同时监听 4174，
  并对 `/v1/` 注入 operator bearer、对 `/v1/audit` 注入 audit token、对 `/h3`、`/h3r`
  注入 vLLM API key。

### 4.2 MoonGate 断链与端口劫持

- **残留 CNI hostport DNAT**：`CNI-DN-38af2fd…` 把所有 dport 5000 的流量（含 loopback）
  DNAT 到已死的 Pod IP，导致 MoonGate 在 `ss` 里可见却连不上
  → 删除该跳转规则并清理链。
- **信任域**：MoonGate 只信任 loopback 的 Host。集群内调用会被
  `moongate_untrusted_request_authority` 拒绝
  → 让 hostNetwork nginx 在 5889 上代理到 `127.0.0.1:5883` 并重写
  `Host: localhost:5883`（同时把 MoonGate 从 5000 迁到 5883，给 ComfyUI 让出 5000）。
- **controller 链路**：traefik→宿主 5888→socat→`127.0.0.1:5880`（无监听）。
  → 新建 systemd user 服务 `lunanexa-control-forward`（`kubectl port-forward svc/lunanexa-control 5880:8080`）。

### 4.3 命名空间 NetworkPolicy 静默丢包

- **症状**：ComfyUI 从任何外部客户端都连不上（宿主机本机 curl 却返回 200），
  抓包显示 SYN 到达节点后无任何回包。
- **根因**：`aigc-acceptance-20260915` 的 `default-deny` 策略按源地址丢弃入站：
  先补 `192.168.2.0/24` 让内网通，公网源是路由器出口 `106.39.18.146`
  （未 SNAT），仍需单独放通。
- **修复**：新增 `comfyui-acceptance-ingress`（放通 `192.168.2.0/24`、
  `106.39.18.146/32`、Pod/Service 网段到 8188）；出口侧另有
  `comfyui-acceptance-egress` 允许 DNS 与 `192.168.2.175:4174`。
- **附带**：宿主机上遗留的 `moon-public-port-forward.py` 占着 5000 转发到已失效目标
  → nginx 在 `127.0.0.1:5000` 接管并转发到 ComfyUI Service。

### 4.4 200Gbps 直连链路

- **IP 丢失**：手工 `ip addr add` 的地址会被网络栈重置清掉
  → 写入 `/etc/netplan/60-lunanexa-cx7.yaml` 并 `netplan apply`
  （`.176`：`192.168.100.10/24`、`192.168.101.10/24`；`.177`：对应 `.11`）。
- **host key**：`.176`→`.177` 的 known_hosts 记录失效
  → `ssh-keygen -R` 后以 `-o StrictHostKeyChecking=accept-new` 重建。
- **rsync 截断**：`--inplace` 在链路中断后留下同长度但内容损坏的文件
  → 改用 `--partial` + 默认临时文件方式，并用 `-c/--checksum` 全量校验。

---

## 5. MiniMax-H3 推理服务

### 5.1 镜像缺少 SM121 补丁

- **症状**：`RuntimeError: Orchestrator initialization failed:` 且信息为空；worker 真实错误为
  `TypeError: MiniMaxH3Attention._install_qkv_weight_loader.<locals>._weight_loader()
  takes 2 positional arguments but 3 were given`。
- **根因**：`lunanexa-cache/vllm-omni-h3:20260914` 由原始 `vectie/vllm-omni` 构建，
  未包含 `single-spark` 仓库的 `patches/minimax_h3_transformer.py`
  （修正 `load_weights` 的 QKV 行归一化、把在线 FP8 的激活量化绑定到 CUDA 实现等）。
- **修复**：把补丁文件做成 ConfigMap 挂载进容器，启动命令先覆盖镜像内同名模块再
  `exec vllm serve`；启动日志可见
  `MiniMax H3 bound 260 FP8 activation quantizers to native CUDA.`

### 5.2 Ref2VA 权重分片本身是截断的

- **症状**：`SafetensorError: Error while deserializing header: incomplete metadata,
  file not fully covered`，Pod 反复重启。
- **定位**：自写脚本校验 safetensors 头部与字节覆盖，发现两侧同为
  `transformer/model-00009-of-00013.safetensors` 异常（期望 5,164,578,896 字节，
  实际 3,640,655,872，差 1.52 GB）——**`.176` 上的原始副本就已损坏**
  （管理机 `/data/models/minimaxh3` 的副本完整）。
- **修复**：从管理机重传该分片（`scp` → `sudo cp`，因目标文件属 root），
  校验 29/29 通过，再经 200G 链路同步到 `.177` 并复校。

### 5.3 部署参数与验收

- 启动参数取自 `single-spark` 仓库的验证配方：
  `--quantization fp8`（GB10 统一内存 ~121 GiB，BF16 单分区装不下）、
  `--diffusion-attention-backend CUDNN_ATTN`、`--force-cutlass-fp8`、
  `--stage-init-timeout 1800 --init-timeout 2400`，env 含
  `VLLM_WORKER_MULTIPROC_METHOD=spawn`、`FLASHINFER_DISABLE_VERSION_CHECK=1`、
  `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`。
- 冷启动约 10 分钟 → startupProbe 设 60×30 秒。
- **端到端验收**（走 ComfyUI 将调用的对外地址）：

```
POST http://127.0.0.1:4174/h3/v1/videos/sync
  prompt/width=768/height=448/steps=20/flow_shift=12/seed=42/fps=24
  extra_params={"task":"t2va","duration":2.0,"audio_flow_shift":3.0}
→ HTTP 200，116 秒，628,836 字节合法 MP4（magic = ftypisom）
```

  `.176` 服务 FL2VA、`.177` 服务 Ref2VA，`/v1/models` 分别返回
  `/models/MiniMax-H3/FL2VA` 与 `/models/MiniMax-H3/Ref2VA`。

---

## 6. 操作事故与教训

- **误清空工作区**：为还原格式器 churn 执行了
  `MINE=$(git diff --name-only)` 后再按名单 `git checkout`，但变量为空导致所有文件
  （含自己的改动）被还原。已从 `/tmp/lunanexa-src2.tar.gz` 快照与 spark 上的副本
  （`~/src`、`~/control-build/src`）完整恢复并复核。
  **教训**：还原名单必须写死，不能从当时的 `git diff` 派生。
- **格式器 churn**：本机 `moon fmt` 会去掉单行记录里的尾逗号，仓库级执行会改写 234 个
  文件。收尾时只保留自己改动的 8 个文件，并进一步把 `ui/console.mbt` 还原为
  最小 2 行 diff。
- **验证口径**：`moon check cmd/console ui --target js --deny-warn --warn-list +73` 通过，
  `moon test cmd/console ui --target js` 101/101 通过；native 侧在本机不可用
  （工具链解析阻塞），改在 spark 上以 `moon info --target native` 验证 0 错误。
- **前端验收方式**：不再用 curl 推断页面行为，改用 Chromium 无头 + CDP 读取真实
  DOM（`hasLogin`/`hasRoot`/节点名/请求完成状态），这才是「页面能不能用」的证据。

## 7. 仍然遗留

- 控制台免登录依赖网关注入 operator 权限，且**当前无 TLS**：任何能访问 4174 的人
  等同运维身份。
- `ui/pkg.generated.mbti` 与 `node/pkg.generated.mbti` 未回写两个新增公开字段
  （需在可运行 `moon info` 的环境生成）。
- ComfyUI 走的是验收命名空间里的实例，尚未接入 LunaNexa 的媒体绑定与商业链路
  （`LUNANEXA_MEDIA_BINDINGS_FILE` 未启用）。
- 双 Spark 张量并行（USP2）未做：上游 diffusers 执行器不支持跨机，仅列为可选实验。

---

## 8. 后续一轮：节点下线、状态抖动与告警治理（2026-09-19 下午）

### 8.1 永久下线节点 `.180` 的身份清理

- **问题**：`lunanexa-gpu-180` 已永久离线，但 `/v1/nodes` 仍显示它，控制台节点页始终
  出现一台不可达机器；控制面没有删除节点的 API。
- **做法**（先备份、再停机窗口内改库）：
  1. `kubectl scale deploy/lunanexa-control --replicas=0`（避免运行中的控制面覆盖改动）；
  2. 备份 `control` 与 `node_enrollment` 两个域的 JSON 快照到 `/tmp/snapshot-*`；
  3. 从 `control` 域移除该节点的 `heartbeats`、`assignments`、`node_directives` 条目，
     从 `node_enrollment` 域移除其 `authorities` 与 `certificates`；
     写回用 `psql -f` + dollar-quoting，避免 shell/JSON 转义问题；
  4. 恢复副本数并复核 `/v1/nodes` 只剩四台 spark。
  脚本：`~/spark-build/retire-node.py <node_id>`。
- **待补**：控制面应提供 operator 级的节点注销 API（例如
  `POST /v1/nodes/{id}:retire`），否则每次下线都要人工改库。

### 8.2 节点“时断时续”其实不是掉线，而是判定阈值过紧

- **测量**：agent 每 5 秒推一次心跳，实际观测到的“心跳年龄”在 1–14 秒之间抖动
  （受调度、数据库写、对端请求影响），而控制面与前端都按 **15 秒**判定不可达，
  于是频繁在 Active / Unreachable 之间翻转。
- **根因二**：前端里另有三处写死的 `15000L`（`cmd/console/main.mbt` 的节点行状态、
  可达节点过滤、时间格式化），与控制面设置各判各的。
- **修复**：
  - `admin-settings.json` 的 `control_timing.heartbeat_timeout_ms` 由 `"15000"` 提到
    `"60000"`（允许上限 300000），即容忍 12 个心跳周期；
  - 前端把三处常量收敛为一个 `node_heartbeat_stale_ms`（与控制器设置对齐），
    并在行内展示“最近上报”而非直接翻状态。
- **配置陷阱**：该文件里 **Int64 必须以字符串书写**（`"60000"`），写成数字会触发
  `SettingsError.InvalidGlobalSetting` 并让控制面 CrashLoop。同类陷阱此前在
  `/v1/enrollment/tokens` 的 `expires_unix_ms` 上也出现过。
- **关于“在节点常驻服务定时推送”**：节点侧本来就是**推送**模型——`node-agent`
  每 5 秒把心跳写入控制面（`POST`），控制面再保存；不健康判定由控制面按
  `heartbeat_timeout_ms` 做。真正缺的是**浏览器侧**的推送：控制台目前是
  `GET /v1/nodes` 轮询。要做到“真正推送”，需要在控制面新增 SSE/WebSocket 端点
  （例如 `/v1/nodes:stream`），把心跳变更广播给已连接的浏览器；本轮未做，
  因为阈值修正后状态已稳定（实测采样全为 Active，心跳年龄 1.6–11.0 s）。

### 8.3 告警数量与查询方式
- **现状（现场清理后）**：告警共 206 条，全部 Resolved；其中 204 条是 `NodeUnreachable`
  （`ClusterHealth` 主题），另有 1 条 `ControllerRecoveryIncomplete`、1 条
  `WorkloadAdmissionRejected`。按 UTC 日分布：09-18 有 179 条、09-19 有 11 条，
  其余 16 条散落在 08-27…09-04。
- **churn 机制**：`api/notification_http.mbt::refresh_node_health_notifications` 在节点
  恢复时把告警 resolve，下一轮又不健康时**重新入队一条新告警**（保留历史），
  因此每次抖动都会留下一条记录，长期累积成噪音。
- **已完成的修复**：
  - 前端告警页增加时间窗口选择器（今天 / 7 天 / 30 天 / 全部，**默认今天**）
    并按 UTC 日分组渲染，未选中的历史不渲染；
  - 窗口状态放在 `AppModel.alerts_window`（不能放进 `ConsoleState`：
    `ui/console_test.mbt` 用完整记录字面量构造它，加字段会编译失败）；
  - 窗口是纯投影，不触发控制面查询；
  - 现场清理：把当时所有未解决告警走 `POST /v1/notifications/operator/{id}:resolve`
    标记为已解决（含那条属于已下线 `.180` 的告警），现 206/206 Resolved。
- **待补**：churn 本身没改——控制面仍会在每次抖动时新建告警，长期仍会累积；
  正确做法是让 `refresh_node_health_notifications` 复用未解决的既有告警，
  而不是每轮新建。


### 8.4 首屏加载剖析（真实浏览器测量）

用 Chromium 无头 + CDP 采集导航时间线（WAN 访问 `:4174/console/`）：

| 事件 | 时间 |
|---|---|
| 页面外壳（`.console-root` 之外的 shell）渲染 | 0.5 s |
| 16 个核心读请求**并发发出** | 0.18 s |
| 第一个响应头返回 | 0.38–0.64 s |
| 最后一个响应头返回 | 15.7 s |
| 首个完整控制台渲染 | 30.1 s |
| 屏蔽全部 `/v1/*` 时的 shell 渲染 | 1.0 s |

结论：
- **JS 不是瓶颈**：屏蔽数据请求后 1 秒内渲染完成；`console.js`（714 KB gzip）实测 0.12–0.18 秒。
- **瓶颈是响应字节数与单线程控制面的串行处理**：核心集合约 250 KB，其中
  `/v1/notifications/operator` 137 KB、`/v1/telemetry` 56 KB，其余合计约 40 KB；
  响应按序返回（0.4→15.7 s），说明控制面侧逐个处理，客户端只能等。

据此做的调整：
- 把 `/v1/notifications/operator` 与 `.../deliveries` 移出核心集合，归入新的
  `AlertsReads` 组，只在打开 Alerts 页时拉取（首页的告警计数在最坏情况下先显示 0）；
- 阈值统一为 `node_heartbeat_stale_ms = 60000`，消除节点状态抖动；
- nginx 缓存策略：`/console/index.html` 与 `/console/` 保持 `no-store`，
  `/console/console.js?v=<digest>` 与 `/assets/**`（含 4 MB 合同字体）改为
  `public, max-age=604800`，避免每次访问重下 714 KB + 4 MB；
- `assets/fonts/contract-fonts.css` 的 `font-display` 由 `block` 改为 `swap`，
  中文字体未到达时不再整段隐藏文字。

仍然存在的限制：首次访问（空缓存）在该 WAN 上仍需十几秒才能看到完整数据；
进一步优化需要控制面提供带时间窗/上限的告警查询、或把响应压得更小。

### 8.5 首屏从 30 秒降到 7–9 秒：一次真正的重复请求 bug

按 8.4 的线索继续挖，用 CDP 记录每一个 `/v1/*` 请求（而不是按路径去重），发现首屏
其实发了 **两轮共 26 个请求**：

| 轮次 | 发出时间 | 内容 |
|---|---|---|
| 第一轮（prefetch） | 0.07 s | 13 个核心路径，服务端串行处理，最后一个响应体在 17.0 s 到齐 |
| 第二轮（真实读） | 8.5 s 起 | 13 个路径**再发一遍**，且逐个 await，前后耗时约 12 s |

- **根因**：`prefetch_get` 把 13 个 Promise 存进 `globalThis.__lunanexaGetCache`，
  而 `request()` **从来没有去读这个缓存**，直接 `request_promise(...)` 重新发请求。
  也就是说 prefetch 一直是纯粹的双倍开销；加上控制面本身串行处理，
  第二个 13 请求的波峰把首屏拖到 26–30 秒。
- **验证控制面确实串行**：13 个路径并发 curl，总耗时 13.2 s ≈ 逐个耗时之和
  （readiness 2.16 s、registry 2.84 s、nodes 1.66 s、assignments 1.41 s、…）。
  并发预取不会变快，唯一有效的手段是**少发请求**。
- **修复一：补上缓存消费**。新增 `extern "js" fn get_promise(url, token)`：
  GET 先查 `__lunanexaGetCache`，命中就取走并 `delete`（保证后续刷新仍是新数据），
  未命中才发请求；`request()` 在 `verb == "GET"` 时走它。同时把 `/v1/readiness`
  从 prefetch 列表删掉——它由 `readiness_request_promise` 单独读取（需要保留 503 的
  响应体），预取它等于白发一次。
- **修复二：继续按路由懒加载**，新增两个读组（沿用 `AlertsReads` 的现成机制）：

  | 读组 | 路由 | 路径 | 字段 |
  |---|---|---|---|
  | `AccessReads` | Users / Leases | `/v1/accounts`、`/v1/accounts/trial-summary`、`/v1/onboarding/access-packages`、`/v1/workspace`、`/v1/exclusive-node-leases` | accounts、trial_summary、access_packages、users、access_grants、compute_leases、exclusive_node_leases |
  | `DeploymentReads` | Catalog / Deployments | `/v1/assignments`、`/v1/service-deployments` | deployments、service_deployments |

  核心集合只剩 6 个请求：`/v1/nodes`、`/v1/registry`、`/v1/scheduler`、`/v1/telemetry`、
  `/v1/catalog/templates`（+ 单独读的 `/v1/readiness`）。
  `DeploymentReads` 的 loader 会自己再读一次 `/v1/nodes`，因为每行 `observed` 状态
  要与心跳里的 `running_deployments` 比对，不能从核心状态近似。
  `merge_loaded_console` 同步扩展了保护列表，核心刷新不会抹掉已合并的分组。

- **实测结果**（同一台机器、同一个 WAN、无头 Chromium + CDP）：

  | 指标 | 修复前 | 修复后 |
  |---|---|---|
  | 首屏 `/v1/*` 请求数 | 26（两轮） | 6（一轮） |
  | 最后一个响应体到齐 | 14.0–17.0 s | 7.2 s |
  | 首个完整控制台渲染 | 26.5–30.1 s | **7.4–9.0 s** |

  逐页复测（每个分组只拉一次，返回 Overview 再进第二次不会重复拉取）：
  Audit 单次 `/v1/audit`（1458 条事件）、Alerts 单次 `/v1/notifications/operator`
  （默认“今天”窗口：`11 of 206 incidents shown`，与库里 2026-09-19 的 11 条一致）、
  Models 单次 import 列表、Catalog 触发 `DeploymentReads`、Users 触发全部 5 条
  `AccessReads`（10 users · 14 grants）、Leases 复用同一分组（28 行）。

现场复核：`/v1/nodes` 为 4 台 spark（心跳年龄 1.6–11.0 s，全部 Active，无 `.180`）；
告警 206 条**全部 Resolved**，按 UTC 日分布 2026-08-27…09-19，其中 09-18 有 179 条、
09-19 有 11 条——这正是“默认看今天”能把首屏告警量从 206 条压到 11 条的原因。

仍然存在的限制：控制面是串行处理请求（一次只服务一个连接），因此首屏时间仍约等于
核心 6 个请求的**串行耗时之和**；要让首屏进入 2 秒级，需要控制面并发处理请求或提供
批量聚合端点，这属于控制面改动，本轮未做。
