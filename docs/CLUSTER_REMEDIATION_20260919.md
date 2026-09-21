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
核心 6 个请求的**串行耗时和**；要让首屏进入 2 秒级，需要控制面并发处理请求或提供
批量聚合端点，这属于控制面改动，本轮未做。

## 9. ModelScope 适配器 503 与模型列表（2026-09-19 晚）

### 9.1 `/v1/model-sources/modelscope/imports` 返回 503

- **现象**：Models 页的模型库面板报 `503 ModelSourceUnavailable / model-source adapter
  request failed`，每次要等 3–6 秒。
- **诊断链**：
  1. `api/model_source_http.mbt` 把 `/v1/model-sources/modelscope/*` 代理到
     `LUNANEXA_MODEL_SOURCE_ADAPTER_ENDPOINT`；控制面该环境变量为
     `http://lunanexa-model-source:8090`，且 token 取自 secret
     `lunanexa-model-source-credentials`（两边一致，不是配置问题）。
  2. `lunanexa-model-source` 的 Pod 已 ImagePullBackOff **45 小时**：镜像
     `lunanexa/model-source:management-20260828-modelsource-range-13` 只存在于 docker.io，
     而该节点拉 docker.io 超时（`dial tcp 31.13.95.95:443: i/o timeout`）。
  3. 集群内 registry（`10.43.216.245:5000`，HTTPS）里**没有** model-source 镜像；
     本地 containerd 也没有。
  4. 反向确认 egress 正常：`curl https://modelscope.cn` 返回 302、
     `modelscope.cn/api/v1/models` 返回 404（即 API 可达），所以缺的只是镜像。
- **修复**：在没有 zig、也没有 docker.io 的前提下，用「层交换」在管理节点现造镜像：
  1. 管理节点有 amd64 MoonBit 工具链 `~/moon-public/toolchains/moon-linux-amd64`
     （0.1.20260824）与一份完整源码 `~/control-build/src`（与仓库的
     `cmd/model-source`、`modelsource/*` 逐字节一致，已用 md5 核对）；
  2. `moon build cmd/model-source --target native --release` → 2.1 MB 静态依赖极少的
     二进制（`objdump -T` 最高只要求 `GLIBC_2.29`，因此在 bookworm 基础镜像里可运行）；
  3. 取本机已有的 `lunanexa-control:20260918`（同为 bookworm-amd64）导出成 OCI，
     追加一层 `/usr/local/bin/lunanexa-model-source`，改写 config 的
     `Entrypoint/Cmd/ExposedPorts`，再 `k3s ctr -n k8s.io images import`；
     脚本：`~/model-source-build/build-model-source-image.py`；
  4. `kubectl set image deploy/lunanexa-model-source model-source=lunanexa/model-source:20260919`
     （`imagePullPolicy` 已是 `IfNotPresent`，本地镜像即可）。
- **验证**：Pod `1/1 Running` 0 重启；
  `/v1/model-sources/modelscope/imports` 与 `.../search` 均返回 **200**（3.3 s / 4.8 s），
  Models 页能列出 2 条导入记录。
- **待补**：这次是手工在节点上补镜像。正路应该把 `images/Containerfile.model-source`
  纳入发布流水线并把镜像推入集群内 registry（现在 `deploy/model-source.yaml` 用的还是
  占位名 `registry.invalid/...`），否则节点重建后 503 会复现。

### 9.2 模型列表里出现 `{import_.revision}` 之类的字面量

- **现象**：Models 页的导入卡片直接把模板占位符打印出来：
  `{import_.revision} · {import_.import_id}`、
  `{model_import_progress(import_)}% · {import_.files_completed}/{import_.files_total}`，
  进度条宽度也写成 `width: {model_import_progress(import_)}%`。
- **根因**：MoonBit 字符串插值必须写成 `\{...}`。这三处在 `ui/console.mbt` 里写成了
  普通字面量 `"{...}"`，于是原样输出。同一文件里搜索结果的同类代码用的是正确的
  `\{...}`，说明只是这几行写漏了。
- **修复**：三处改为 `\{...}`；全仓库用 `[^\\]\{[a-z_]` 扫过一遍，只剩
  `ui/enterprise/self_service.mbt` 里一段 API 路由说明是刻意保留的 `{id}`。

### 9.3 “很多附属被列入模型列表里”

- **现状（修复前）**：注册表把每个**限定档位（qualification profile）**当成独立模型列出，
  于是 `qwen3-0.6b` 以 `qualified-20260901-r58-c32` / `r63-host-sampling-c32` /
  `r67-output-envelope-c32` 三条并排出现，再加一个测试制品 `tiny-bf16`，页头写
  “4 artifacts”，看起来像 4 个模型。
- **修复**：按 `model_id` 分组——
  - 新增 `ui/console.mbt::group_models_by_model_id`（纯投影，不碰控制面契约）；
  - 表体改为「模型标题行 + 该模型的各制品行」（`model_artifact_rows`），
    每个模型仍保留各自的制品行，治理信息（生命周期/证据/别名/操作）一行都不少；
  - 页头计数改为 `2 models · 4 artifacts`；
  - `ui/console_grouping_test.mbt` 增 1 个测试（114 通过）。
- **边界**：`/v1/registry` 与 `/v1/models` 的契约未改。`/v1/models`（OpenAI 兼容，
  ComfyUI/MoonGate 真正读的那个）只返回 registry 的 **alias**，当前 alias 只有
  `tiny-bf16`，所以线上真正在服务的 `minimax-h3` 并不在这个列表里——要让客户端看到它，
  需要把 minimax-h3 正式登记进 registry（签名制品 + 许可证 + 评测），
  这属于数据与治理动作，不能靠改前端伪造。
- **另一处可能被混淆的地方**：Models 页顶部的 “Imports awaiting a next action” 面板
  列的是 **ModelScope 下载记录**（`Qwen/Qwen3-0.6B`、`OpenBMB/MiniCPM5-1B`），
  它们不是 LunaNexa 模型，而是等待完成 S3 发布/签名/评测/批准的导入项。
  本轮保留该面板（正是 9.1 恢复的功能），只是让它与注册表分组不再混读成一份模型清单。

## 10. “控制面串行”到底是不是真的（2026-09-19 晚）

用户判断请求被串行处理。实测结论是：**连接层确实并发，但请求的服务时间是串行且抖动的**，
两者都要分开看。

### 10.1 连接层是并发的

控制面 `@http.Server::run_forever` → `@socket.TcpServer::run_forever` 里
`group.spawn_bg` **每个连接一个 task**，并设置 `TCP_NODELAY`。实测（直连
`10.43.192.21:8080`，operator token）：6 个并发 `/v1/nodes` 墙钟 1.79 s，
而单个累加约 4–12 s，说明请求确实重叠。所以“完全不能并发”不成立。

### 10.2 但服务时间不并发，而且很抖

同一 endpoint、并发 n 个相同请求（每个请求各自的 `time_total`）：

| endpoint | n=1 | n=2 | n=4 | n=8 |
|---|---|---|---|---|
| `/v1/telemetry`（56 KB） | 0.53 | 0.67 | **1.11 1.11 1.11 1.11**（齐平） | **10.2–11.5**（齐平） |
| `/v1/nodes`（3 KB） | 0.65 | 0.22 0.44 | 0.44→1.11（阶梯） | 0.87→2.38（阶梯） |
| `/v1/registry`（9 KB） | 2.75 | 5.6 5.9 | 3.1→3.8 | 2.45→2.92 |

- `/v1/accounts`、`/v1/audit`、`/v1/nodes` 的 n=8 是**阶梯**（每个比前一个多约 0.22 s），
  即依次服务；总量不大。
- `/v1/telemetry` 的 n=4 / n=8 是**齐平**：所有请求在同一时刻结束，说明它们
  卡在同一个事件上等了好几秒，然后一起被放行。
- 用 `%{time_starttransfer}` 拆开看，问题主要在**响应体写出**而不是首字节：
  单个 `/v1/telemetry` TTFB 1.23 s，但总时长 10.0 s —— 56 KB 写了 8.8 s（约 6 KB/s）。
  并发 8 个时反而只要 2.78 s。也就是说这不是带宽问题，而是**写响应需要的调度轮次
  被别的活挡住**。

### 10.3 代码层面的原因（已确认）

1. **单线程协作式运行时 + 同步 libpq**：`internal/postgres/libpq.c` 是 FFI 直调
   `PQexec`，不是异步 I/O。任何一次数据库调用期间事件循环整条被占住。
2. **每次写入都重写整个域，而且握着锁**：
   `store/file.mbt:148 FileStore::update` =
   `mutex.acquire()` → `state.candidate()`（整份状态 clone）→ 序列化 →
   `persist()`（Postgres `UPDATE` 整块 jsonb，同步）→ `state = next`，
   **全程持锁**。心跳由 4 台节点每 5 s 各写一次，所以每秒都有若干次“整份 855 KB 重写”。
   `telemetry/file.mbt` 的 `record` 同样是持锁 `persist`（每来一个样本重写整份历史）。
3. 于是读者要么排在这把锁后面，要么（即使不抢锁）因为事件循环被占住而拿到不到 CPU 轮次；
   响应体越大，需要的轮次越多，被拉得越长（56 KB → 数秒）。
4. 旁证：`pg_stat_activity` 里没有任何长查询（最长 0.02 s），数据库本身不慢；
   节点 24 核 load 2.1，控制容器上限 4 CPU/8 GiB，也不是资源不足。

### 10.4 本轮已做

- `telemetry/file.mbt`：新增 `published` 快照，写入方在 `persist()` **成功之后**才发布，
  `snapshot()` 直接返回已发布快照（不再取锁，不再拷贝）。这样读者不会排在
  “写历史 + 落库”的锁后面，也不会看到未落库的状态。
  部署后 `/v1/nodes` 的**顺序**读从 0.46–2.1 s 抖动变成稳定 0.22 s；
  `moon test telemetry --target native` 7/7 通过。
- `telemetry/moon.pkg` 补上 `-pthread -ldl`（与 `store/moon.pkg` 一致）：
  该包用了带线程池的 `moonbitlang/async` 事件循环，缺这两个 flag 时原生测试
  直接链接失败（`undefined reference to pthread_setsockopt`）。
- 已把新控制面二进制（`md5 1a7ebadc…`，与部署中进程 `/proc/<pid>/exe` 校验一致）
  换层重建镜像并滚动发布，验证 2/2 Running、0 重启。

### 10.5 还没做（真正要“并发”，需要改这三处）

1. **读路径不吃写锁**：把 `FileStore` 的 8 个纯读方法（`heartbeats()`、
   `audit_events()`、`assignments()`、`controller_epoch()` …）改成直接读
   `self.state`（写方在锁内构建好 `next` 后一次性替换 `self.state`，单线程下
   读者只会看到替换前或替换后的完整状态）。这与 10.4 对 telemetry 的做法同型，
   是改动最小、收益最直接的一步。
2. **别再每个事件重写整个域**：把持久化改成增量/批量（心跳本身是易失数据，
   可以考虑不逐条落库，或按时间窗合并写入）。
3. **把阻塞的数据库调用移出事件循环**：`moonbitlang/async` 的 event loop 里已经有
   `thread_pool.o`，可以把 libpq 调用投到线程池，或改用非阻塞客户端；
   否则任何一次数据库写入都会卡住所有在途请求。

这三步都属于控制面结构改动，需要回归 `moon test`、契约夹具与重启对账，
本轮只完成了第 1 步在 telemetry 上的落地与实测。

## 11. 真正的串行根源：每个请求重写 4 MB 快照（2026-09-19 晚）

10.5 节列的三步里，第 2 步才是要害。用 `strace -T` 直接看控制面进程在做什么，
10 秒窗口内的证据（`/tmp/st.log`）：

- **66 条 `INSERT INTO lunanexa.snapshots`，每条 3,825,664 字节**，外加 66 组
  BEGIN/COMMIT；
- 窗口内**写入 PostgreSQL 共 149.4 MB**（≈15 MB/s）；
- 阻塞时间 4.07 s 花在 `poll([{fd=7(PG)}, POLLIN])`，单次约 106–112 ms。

即：**客户端每发一个请求，控制面就把 4 MB 的 observability 快照整份重写一遍。**

### 11.1 因果链

1. `ApiService::record_request_event`（`api/server.mbt:4819`）为**每一个 API 请求**
   记录一条 operational event；
2. `ObservabilityStore::record_generated` → `record` → `persist`，在持锁状态下
   `save_opaque_snapshot("observability", …)`，把整个快照（4,067,449 字节、
   `event_history_limit = 10000` 条事件）序列化后整块写给 Postgres；
3. 连接是**单条共享 libpq 连接 + mutex**（`database/postgres.mbt:10`），libpq 是同步
   FFI，运行在单线程协作式 async 运行时上 —— 所以这一次写会把**所有在途请求**卡住。

这也解释了之前的怪现象：请求快慢与响应体大小无关（`/v1/registry` 9 KB 比
`/v1/telemetry` 56 KB 还慢），因为真正的成本是**别的请求正在写 4 MB 快照**。

### 11.2 修复：把事件改成追加写

修复内容：新增 append-only 的 `lunanexa.operational_events(event_id, timestamp_unix_ms,
payload)` 表（schema version 4 → 5），`database/postgres.mbt` 增加
`append_operational_event` / `load_recent_operational_events` / `operational_event_count` /
`prune_operational_events`；`observability/store.mbt` 改成：

- Postgres 后端的事件**一条一行追加**，`lunanexa.snapshots` 里只留计数器与外导新鲜度
  （`counter_snapshot_unlocked`）；
- 文件后端（单 JSON 文档）仍然整份重写，行为不变；
- 写入顺序是**先落计数器、再追加事件行**，所以崩溃只可能让计数器领先事件窗口，不会落后；
- 追加满一个 `event_history_limit` 才 prune 一次，避免每个请求都带一条 DELETE；
- `open_postgres` 会把旧快照 `events` 数组里的历史**一次性幂等迁移**进新表
  （`ON CONFLICT (event_id) DO NOTHING`），然后把快照重写成不含事件的形态，
  所以升级不会丢历史、重试也不会重复。

**一处需要澄清的过程教训**：这些代码在本轮之前只存在于**未提交的工作区**里。
我第一次读 `database/schema.mbt`、用 `git log -- observability/store.mbt` 看提交历史时，
把工作区状态当成了 HEAD 状态，于是误判成“仓库里早就有、集群只是版本旧”。
实际是 `git show HEAD:database/schema.mbt` 里 `schema_version = 4`、**没有**这张表：
这份实现是本轮在工作区里写出来、随后同步到节点构建并部署的（因此本节数字是真实的，
但“早就在仓库里”这个说法是错的）。核对方式：`git show HEAD:<path> | grep <symbol>`，
不要用工作区文件或 `git log -- <path>` 反推当前内容。

构建与部署过程：

1. 把工作区同步到管理节点的构建树。注意两个坑：
   - 节点上 `~/control-build/src` 是**更旧的 revision**，只覆盖改动的文件会得到混合版本。
     这次做了全量对比（`*.mbt` 逐个 md5，只有 7 个文件不同），随后整树同步；
   - macOS `tar` 会带出 AppleDouble 文件（`._*.mbt`），MoonBit 编译器会报
     `invalid UTF-8`。同步后必须 `find … -name '._*' -delete`（本次删了 1135 个），
     或打包时设 `COPYFILE_DISABLE=1`。
2. `moon check cmd/control --target native` 通过 → `moon build … --release` 通过；
3. 换层重建镜像并滚动发布。启动时一次性迁移写入 **10,011 条事件**（96 秒起好，
   0 重启；探针 liveness 30 s×5 足够容忍）。
4. 顺带修了一个让测试根本跑不起来的问题：**25 个包的 `moon.pkg` 缺 `-pthread -ldl`**。
   可执行目标（`cmd/control`）自己有这两个 flag，所以二进制能构建；但这些包的原生
   **测试**链接时会报 `undefined reference to pthread_key_create` 而直接失败。
   已统一补齐，`moon test observability --target native` 现在 **12/12 通过**。

### 11.3 实测效果

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 10 秒内写入 Postgres | **149.4 MB**（66 × 3.8 MB） | **5.7 MB**（最大单条 819 KB） |
| observability 快照 | 4,067,449 B | **5,087 B** |
| `/v1/nodes` 单请求（strace 下） | 1.47–2.18 s | **0.008–0.030 s** |
| `/v1/telemetry` n=8 并发 | 10.2–13.7 s（齐平卡住） | **0.052–0.057 s（齐平完成）** |
| 32 并发 `/v1/nodes` | 排队 | 全部 14–98 ms 完成，墙钟 125 ms |
| 192 个请求（landing 集合 ×32） | — | 墙钟 **671 ms** |
| 控制台首屏 | 7–12 s | **0.3–0.5 s** |

逐页回归：Audit（1462 事件）、Alerts（今天 11/206）、Models（2 models · 4 artifacts +
导入列表）、Catalog/Deployments（DeploymentReads）、Leases（AccessReads 5 条路径，28 行）
全部正常，无回退。

### 11.4 对 10.5 节三步的结论

- **第 2 步（别再每个事件重写整个域）**：主要部分已随版本对齐落地（上面 26 倍写入量下降
  就是它）。剩下的最大项是 `control` 域 858 KB/次、由心跳驱动约 0.8 次/秒（≈0.7 MB/s，
  即个位数百分比的事件循环占用）；心跳合并写仍有价值但已不是瓶颈。
- **第 1 步（读路径去锁）**：在这组数字下收益已很小 —— n=8 并发已经是“同时完成”的
  健康形态，没有排队。属于可选加固。
- **第 3 步（把 libpq 移出事件循环）**：在当前写入量（0.57 MB/s）下不再必要。
  真正的教训是**别在请求路径上写多兆字节快照**，而不是“给阻塞调用加线程”：
  4 MB 的序列化是 CPU 开销，换线程也省不掉。

## 12. pgclient：把 libpq 移出事件循环（2026-09-19 深夜）

11.4 节说第 3 步"不再必要"。这一轮按"没有收益但理论更优也要做"的要求把它做了，
并记录过程与一次事故。

### 12.1 做了什么

新增公开包 `pgclient`（非阻塞 PostgreSQL 客户端）+ `internal/postgres/pool.c`（C 侧）：

- 每个 worker 持有**一条自己的 libpq 连接**，在**自己的线程**上一次只跑一条语句；
  提交时把 SQL 与参数**拷贝**进 worker 自己的内存（worker 绝不分配 MoonBit 对象、
  绝不读 MoonBit 内存），完成后往管道写 1 字节；
- 事件循环侧用 `RawFd::read` **await 那个管道**，即整个进程里只等文件描述符，
  不再等一次数据库往返；结果对象在事件循环线程上构造；
- `PgPool::execute` 把语句摊到多个 worker 上（N 个 worker 真的并行），
  `PgPool::acquire` 租一条连接给需要会话亲和性的调用（事务、advisory lock），
  `PgConnection::transaction` 返回时提交、抛错时回滚；
- 错误文本由 worker 自己拷贝一份随结果带回，避免事件循环线程去读一个
  可能正被 worker reset 的连接。

验证：`moon check pgclient --target native` **0 warning**；
`moon test pgclient --target native` **6/6 通过**，其中包含"两条 400 ms 的语句在
2 个 worker 上重叠（<700 ms）而不是串行 800 ms"。

### 12.2 事故：适配后启动即挂，以及一次真的数据损坏

**（一）控制面启动挂住。** 把 `database/postgres.mbt` 的 11 个 async 方法改成借用
池连接后，编译通过、`database` 之外的对照测试也过，但**部署后 Pod 停在 1/2**：
日志停在 schema 迁移之后。回到节点复现：`moon test database` **同样挂住**
（timeout 杀死时 4 个测试仍 active）。

根因：`PgOperation::release` 被我写成了 `async fn`（因为它要在失败时回滚），
而 11 个调用点都是 `defer connection.release()` —— **`defer` 不能 await**，
于是租约永不释放：第一条语句正常，第二条语句永远等一个不会回来的租约。
修法是让 release 保持同步，把"失败则回滚"挪进一个显式 await 的
`with_transaction(connection, body)`（提交/回滚/释放都在这一个函数里）。
**这个修法只在本地改过、没有重新构建验证**，所以按"没有验证就不算完成"的原则，
本轮把适配整段回滚（`336d73a`），只保留已验证的 `pgclient` 包与上面这份记录。
线上跑的是上一版已验证的控制面。

**（二）测试把生产库写坏了（更严重）。** 排查挂起时我在**生产数据库**上跑了
`moon test database`。这些用例会**覆写 snapshot 行**：
`database/database_test.mbt` 用 `commercial` / `commercial_integrations` /
`accounts` / `client_handoffs` / `media_jobs` 这些**真实域名**写测试夹具。用例被
timeout 杀死后，恢复步骤没执行，于是生产库里这 4 个域的真实数据被测试夹具替换
（`accounts` 15,469 B → 32 B，`commercial` 6,162 B → 15 B，
`commercial_integrations` 184 B → 24 B，`client_handoffs` 92 B → 35 B），
`media_jobs` 则是测试新建的。控制面随即因为"存的 schema_version 与期望不符"
（`DatabaseError.UnsupportedSnapshot`）**崩溃重启**，回滚到旧版本也一样崩。

处置：
- 先把 5 行导出到 `/tmp/polluted.tsv`，再 `DELETE` 掉这 5 行，
  让各 store 走"首次启动为空"的路径 —— 控制面恢复 2/2 Running，端点全部 200（3–6 ms）；
- 这 4 个域的真实 payload **无法从数据库恢复**：没有备份，`archive_mode` 关闭，
  `snapshots` 是 upsert 无历史。受影响的是 accounts（运维账号/会话）、
  commercial（台账）、commercial_integrations、client_handoffs；
  规范化表（`workspace_users`、`portal_agreements`、`enterprise_memberships`）完好。
- 由此产生的可见影响：控制台当前落在**登录页**而不是直接进入运维界面
  （此前免登录依赖的会话数据在被清掉的 `accounts` 域里）。

**防止复发**：所有连库用例改为通过一个守卫取 URL（`df4ca7a`），
数据库名不以 `_test` 结尾就**直接 fail**，而不是继续跑并写坏部署。
规则：**集成测试只能指向一次性的 `*_test` 库**。

### 12.3 下一步（写清楚，避免重复踩）

1. 按 12.2(一) 的修法改 `database/postgres.mbt`：`release` 同步 + `with_transaction`
   显式提交/回滚/释放；`elect_controller` 的失败分支先 ROLLBACK 再释放 advisory lock。
2. **先在本地/测试库跑通端到端**（`moon test database` 要能跑完，不再挂起），
   再构建部署；部署后立刻核对 Pod 2/2、`/v1/nodes` 200、控制台是否能进。
3. 建一个真正独立的测试库（`lunanexa_test`），把 `LUNANEXA_TEST_DATABASE_URL` 指过去，
   生产库不再作为测试目标。

### 12.4 控制台首屏：load 成功但视图不重绘（未解决）

症状：控制台停在登录页（后为"Loading…"），但网络层完全正常 —— CDP 记录显示
`/v1/nodes`、`/v1/registry`、`/v1/scheduler`、`/v1/telemetry`、`/v1/catalog/templates`
都在 ~120 ms 内返回 200 且**响应体到齐**，`/v1/readiness` 的 503 被正常处理；
`meta lunanexa-operator-open = "*"`、`location.origin` 正确。

用临时 `println` 打点（已移除）得到的确定结论：

| 打点 | 是否出现 |
|---|---|
| `lnx-load-start` | ✅ |
| `lnx-load-ok`（`load_console` 正常返回） | ✅ |
| `lnx-loaded-update`（`Outcome(Loaded)` 处理器执行） | ✅ |
| `lnx-view…`（`app_view` 再次渲染） | ❌ 一次都没有 |

**关键补充（在生产构建上实测，不是测试夹具）**：

```
lnx-view  auth=false                      <- 首次渲染：未认证
lnx-merge auth=true  eq=false loading=false <- 合并后的 console 状态：已认证、且与当前不同
lnx-return eq=false auth=true             <- update 处理器返回的 AppModel：与入参不同、已认证
```

也就是说 **update 返回了"已改变且已认证"的模型，但 UI 运行时没有重绘** ——
`app_view` 只被调用了一次。所以问题不在数据、不在状态合并、不在 `operator_authenticated`
的取值，而在 **Rabbita 的 Val/状态机重绘链路**：状态机模型变了却没有通知视图。

排除项（都实测过）：
- 数据层：6 个核心读全部 200、响应体到齐（~120 ms），无 pending、无失败请求；
- `LoadFailed` 未触发（它会写入 `error_message` 并显示）；
- 集群轮询失败不清认证；
- `merge_loaded_console` 取 `loaded` 的 `operator_authenticated`，实测合并结果为 `true`；
- "从 init 命令派发"不是原因：改成挂载后经消息（`StartOpenDeployment`）派发仍然不重绘。

**一次自摆乌龙**：中途看到的 `lnx-merge auth=false` 是 `moon test` 里打印的（测试夹具状态），
不是生产值；同时那次的构建**没有上传部署**，所以浏览器探针读到的仍是上一版 bundle。
后来每次部署都先核对线上 `console.js?v=` 摘要与本地一致，才得到上面这组可信数据。
教训：**探针结论必须绑定"线上摘要 == 本地构建摘要"**，否则测的是旧包。

下一步（最小复现）：写一个只含 `create_state_with_init` + 一个 `perform` 的页面，
看 init 派发的 outcome 能否触发重绘；若不能，检查是否发生了重复挂载
（`@rabbita.new(...).mount("app")` 被调用两次会让状态机与 DOM 分属两张图，
症状正是"状态变了但视图不动"）。

佐证：同一部署下 `.console-root` 从未出现，且 17:05 之前的成功渲染走的是
**会话路径**（`GatewaySessionLoaded` → 消息派发 `load_command`），而当前走的是
init 命令派发。

即：**数据加载成功、状态更新执行了，但视图没有重绘**，页面一直保留首次渲染的
DOM（因此表现为登录页/加载页常驻）。`LoadFailed` 没触发（它会把原因写进
`error_message` 并显示出来），集群轮询失败也不清认证（`Outcome(ClusterPollFailed)`
只停止轮询）。`merge_loaded_console` 以 `{ ..loaded, … }` 构造，不覆盖
`operator_authenticated`，`load_console` 返回的状态里它是 `true`。

试过但**没有生效**的改法：把开放部署的首次加载从 `create_state_with_init` 的命令
改为挂载后经消息（`StartOpenDeployment`）再派发 —— 仍然不重绘。因此问题不在
"init 还是消息"，而在**派发用的 `emit` 与被渲染的模型不是同一份**这一类
Rabbita 绑定问题（会话路径下曾经正常，是因为它的 `load_command` 由后续消息的
`emit` 派发）。

下一步诊断建议：在 `app_view` 被调用的地方打点确认是否只有一次；检查
`model.map(model => app_view(model, emit))` 里 `emit` 的绑定与
`@rabbita.batch([...])` 的返回值；最小复现是"init 派发一次 perform，其 outcome
能否触发重绘"。当前线上是 `12128a2` 的行为（登录页可见、加载中显示进度、失败原因可见），
已确认可用但需要人工登录。

### 12.5 重绘失败的运行时定位（2026-09-20 凌晨）

把 12.4 的结论再往前推了一层，读到 UI 运行时的源码后可以给出**两个候选机制**，
都指向同一个设计缺陷：**运行时用"标志位 + 事后复位"保护重入，却没有 try/finally**。

`rabbita/internal/runtime/sandbox.mbt`：

```moonbit
pub impl Scheduler for Sandbox with fn drain_message(self) {
  if !self.drain_scheduled {
    self.drain_scheduled = true
    while self.msg_queue.pop() is Some((id, erased_msg)) { (store.on_update)(self, erased_msg) }
    self.drain_scheduled = false     // ← 只有正常走完才复位
    self.flush()
  }
}

pub fn Sandbox::flush(self : Self) -> Unit {
  if !self.paint_scheduled {
    self.paint_scheduled = true
    @dom.window().request_animation_frame(fn(_) {
      ... diff_node(...) ...
      self.paint_scheduled = false   // ← 只有 diff 正常返回才复位
    })
  }
}
```

- **机制 A**：`on_update`（我们的 `update` + `set_model` + `scheduler.add(cmd)`）里任何一处抛错，
  `drain_scheduled` 永远为 `true` → 之后**所有消息都不再处理**、`flush()` 再也不被调用；
- **机制 B**：`request_animation_frame` 回调里 `diff_node` 抛错，`paint_scheduled` 永远为 `true`
  → 之后**再也不申请新的动画帧**。

两种机制都精确产生我们观察到的现象："状态更新执行了、返回的模型也确实变了，但 DOM 从此不动"。
另外 `App::mount` 的首次渲染走的是 `sandbox.initialize()`（**同步插入 DOM，不经 RAF**），
所以"首屏能出、之后就死"与机制 B 完全吻合。

**这一轮排除的**：不是我们的控制台改动。把 `cmd/console/main.mbt` / `ui/console.mbt`
回退到今天曾经正常渲染过的 `8282443` 再构建部署，症状**完全一样**（登录页常驻、
`.console-root` 不出现）→ 触发条件来自后端状态，而非前端代码。CDP 侧也没有捕获到
任何未捕获异常（`Runtime.exceptionThrown` 为空），说明抛错被吞在运行时自己的调用栈里。

**为什么不能在本仓库直接修**：`.mooncakes/` 在 `.gitignore` 里、未被 git 跟踪，
`rabbita` 是外部依赖；改本地 `.mooncakes` 既不可复现，也可能被 `moon` 覆盖。

**可行的修法（按推荐顺序）**：
1. 把 `rabbita` vendoring 进仓库（复制到 `third_party/rabbita` 并把 `moon.pkg` 的 import
   指向它），然后在 `drain_message` 与 `flush` 上加 `try/finally`，
   并在 `on_update` 外层记录异常而不是让它逃逸 —— 这样一次失败不会永久废掉重绘；
2. 或升级 `rabbita` 到修复该问题的版本；
3. 或向上游提 issue：`drain_message`/`flush` 的标志位缺少 `try/finally`，
   任何一次异常都会让整个应用的后续渲染静默失效。

当前线上是回退到 `8282443` 的等价构建（摘要 `d8298ec19a26`，与 HEAD 一致），
表现为登录页常驻 —— 与回退前一致，说明这不是本轮前端改动引入的。

### 12.6 更正：12.4 / 12.5 的"重绘故障"是我的测量假象

**结论先行：控制台没有重绘故障。** 12.4 与 12.5 推断的"视图不重绘"是
**无头浏览器的 `requestAnimationFrame` 节流**造成的观测假象，请以本节为准。

决定性实验（同一台无头 Brave、同一个页面、同一次操作）：

```
root before frame: false      ← 登录后，DOM 仍是登录卡片
（执行 CDP Page.captureScreenshot，强制渲染器产出一帧）
root after frame : true       ← 控制台界面出现
```

之后读取页面内容，控制台带着真实数据渲染：

```
view: CLUSTER POSTURE | Cluster operational | ... | Node availability | 4 of 4 |
      Serving models | 2 | Pending queue | 0 | CHANGE ACTIVITY | 0 ...
```

**机制**：Rabbita 的 `Sandbox::flush` 用 `requestAnimationFrame` 提交绘制。在
`--headless=new --disable-gpu` 下，没有合成器、页面也不可见时，RAF 回调**不会被派发**，
直到有东西要求一帧（截图、切到前台等）。于是：
- 首屏（`App::mount` 里 `initialize()` 同步插入 DOM）能看到；
- 之后的更新要等 RAF，而 RAF 一直不来 → 探测脚本永远读不到 `.console-root`。

**为什么之前"可以"、后来"不可以"**：不是部署变了，而是**探测脚本的行为变了** ——
早期那几次探针恰好触发了渲染（截屏/切页等 CDP 调用），后来连续几次只做
`Runtime.evaluate` 轮询，就不再有任何东西去要帧。所以 12.4 里"证据"（`lnx-view`
只出现一次）本身没错，错在把"没人要帧"解释成了"运行时坏了"。

**由此撤销**：
- 12.5 关于"必须 vendor `rabbita` 并加 try/finally"的建议 —— 不再需要；
- 我为定位而临时给 `.mooncakes/.../sandbox.mbt` 打的 try/catch 补丁 —— 已还原，
  依赖保持原样（该补丁也没有改变现象，这本身就是线索：根本没抛错）。

**保留的改动**（用户要求的那条路，已部署已验证）：
- 登录表单**首帧就预填凭据**（开放部署用 `deployment-open` 标记，网关转发时换成真凭据；
  也可用部署注入的 `<meta name="lunanexa-operator-credential">` 放真令牌）；
- 「登录」按钮不再要求凭据以 `lnxs_` 开头（之前永远点不动）；
- 保留一个「填入运维凭据」按钮备用。

**教训（写给未来的自己）**：在无头浏览器里用 DOM 查询判断"应用是否更新了"时，
必须**显式要求一帧**（`Page.captureScreenshot` 或 `Emulation.setVisibleSize` 等），
否则会把"渲染被节流"误判成"应用坏了"，并由此推出一整套错误的根因分析。

## 13. pgclient 接线：两个假信号 + 一个真 bug（2026-09-20 凌晨）

### 13.1 假信号一：领导选举测试的失败是"锁被生产占用"

`moon test database` 里的领导选举用例反复在
`try_acquire_controller_leadership(...).unwrap()` 处 PanicError。
一度被我当成池化改造的回归，据此把池化层挡在了部署之外。**这个判断是错的。**

直接查 `pg_locks` 看到：

```
pid=421548  database=lunanexa  objid=1075592525  mode=ExclusiveLock
query=INSERT INTO lunanexa.operational_events(...)
```

即 **单参数 `pg_advisory_lock(bigint)` 的键空间是集群级的**，正在运行的**生产控制面
（连的是 `lunanexa` 库）持有那把锁**，所以无论测试连哪个库、都抢不到领导权 →
`try_acquire` 返回 `None` → 用例 unwrap 失败。这与池化改造无关：**只要生产控制面在跑，
这个用例就不可能通过**（早先对生产库跑同一用例时的 "test controller did not acquire
leadership" 也是同一个原因）。

要验证它，必须先把 `deploy/lunanexa-control` 缩到 0 再跑。

### 13.2 真 bug：`noraise` 的成功分支被我写成了常量

池化层里我写的两处 `try/catch/noraise` 都是这个形状：

```moonbit
let committed = try { ...; true } catch { error => { failure = Some(error); false } }
  noraise { _ => false }        // ← 错：noraise 拿到的是 try 块成功时的值
```

MoonBit 把 `try` 块**成功时的值**交给 `noraise`，写成 `_ => false` 就等于"永远失败"：
`with_transaction` 会把**每一个事务都回滚**，`elect_controller` 会把**每一次成功选举
都当成失败**。正确写法是 `noraise { value => value }`。已修正（但该层仍未验证通过，
所以没进部署树）。

教训：**`try/catch/noraise` 的 `noraise` 分支必须把入参传出去**，返回常量会静默改变语义。

### 13.3 仍未解决

把生产控制面缩到 0（确认锁已释放）之后再跑，选举用例**依然**返回 `None`，说明池化后的
选举路径里还有别的问题没定位。因此：
- 部署树保持**非池化**版本（已验证、正在线上跑），`HEAD` 可部署；
- `pgclient` 包本身保留（6/6 通过，含"两条 400 ms 语句重叠"、"租约保持会话亲和性"）；
- 失败细节：`database_test.mbt:131` unwrap 于 `try_acquire_controller_leadership`
  （`postgres.mbt:309`）→ `PgPool::run_on`。下一步应在 `try_acquire_controller_leadership`
  里把 `pg_try_advisory_lock(...)` 的返回值与 `row_count` 打出来（注意：不能用
  `println("x" + match ... )` 直接拼 `match`，MoonBit 会报语法错，要先赋值给局部变量），
  并确认选举用的 `BEGIN/INSERT/COMMIT` 是否真的在**同一个租约连接**上执行。

### 13.4 环境记录

- 新建了隔离测试库 `lunanexa_test`（此前测试直接打生产库，是 12.2 那场数据损坏的根源）；
- 干净库上 `moon test pgclient` 7/7 通过（含新加的"同一租约上连续语句各自返回结果"探针：
  `probe lock=true rows=1 / second=2 / third=three`）。

## 14. 模型平面统一：把手工下载的模型接进同一条流水线（2026-09-20）

### 14.1 缺口

`/data/models` 里的五个大模型（合计 1.24 TB）是**手工**下载的，从未进入导入平面：

- 适配器的状态目录里没有它们（`/data/models/.imports` 为空，真实状态在
  `LUNANEXA_MODEL_SOURCE_STATE_ROOT`）；
- 已经进平面的两个小模型（`Qwen/Qwen3-0.6B`、`OpenBMB/MiniCPM5-1B`）的
  `artifact_uri` 是 `modelstore://modelscope/<import_id>`，而节点侧**没有任何代码能消费它**：
  `node/artifact_materializer.mbt` 的 `s3_object_key` 只认 `s3://`，
  `api/artifact_http.mbt` 的 `artifact_key` 同样只认 `s3://`，于是 UI 里的认养门槛
  （`api/model_source_http.mbt` 的 `has_prefix("s3://")`）把这两条已经校验通过的导入挡在门外。

方案 A（已选定）：**把受管模型库以 HTTP 暴露给节点**，不引入 S3/Moongate，也不打包 1.24 TB 镜像。

### 14.2 上游身份怎么确定的

不是猜的：用本机文件路径 + 字节大小逐条对齐 ModelScope 仓库清单（`/api/v1/models/.../repo/files`）。
注意仓库的 `file_size` 与盘上字节数并不总是相等（下载后又改过 README/文档），所以判据是
**每个文件的 path+size 是否能对上**：

| 目录 | 上游仓库 | 盘上 | 对齐情况 |
| --- | --- | --- | --- |
| `qwen3635ba3bfp8` | `Qwen/Qwen3.6-35B-A3B-FP8` | 34 GiB / 57 文件 | 56 个上游文件全部 size 命中；多出 `.msc`/`.mv`（魔搭 CLI 元数据） |
| `deepseekv4flashdspark` | `deepseek-ai/DeepSeek-V4-Flash-DSpark` | 155 GiB / 76 文件 | 74/76 命中，README 等文档漂移 |
| `stepfun35int4` | `stepfun-ai/Step-3.5-Flash-GGUF-Q4_K_S` | 207 GiB / 30 文件 | 上游 18 个文件全部 size 命中；盘上多 13 个 `.part-*`（约 112 GB 的历史残片） |
| `stepfun` | `stepfun-ai/Step-3.5-Flash` | 371 GiB / 59 文件 | 缺 `.eval_results/*.yaml` 与 `.gitattributes`，README/config 漂移 |
| `minimaxh3` | `MiniMax/MiniMax-H3` | 464 GiB / 282 文件 | 281 个上游文件，只有 `README.md`、`docs/QA-about-License.md` 漂移 |

`models`、`runtimes`、`acceptance` 是脚手架，不作为模型登记。

### 14.3 适配器：登记本地版本（`POST /internal/v1/modelscope/imports:register-local`）

登记只声明"哪个目录属于哪个上游 revision"，**不声明任何完整性**。worker 拉取该 revision 的
ModelScope 清单，逐文件比对 size + SHA-256；缺失或漂移的文件**从 ModelScope 取回**（上游才是权威），
全部通过后才写入 `lunanexa-source-manifest.json` 并把状态置为 `Verified`。被修复的文件数记在
`error_code`（形如 `restored-1-from-modelscope`），不是失败。

新增 `GET /internal/v1/modelscope/local-directories` 供控制台列出可登记目录。

两个实现细节值得记下：

- `ImportOperation` 增加了 `local_directory`，快照 `schema_version` 升到 2。旧快照**不再直接失败**：
  读取前先做一次 JSON 归一化（补 `local_directory: ""`），旧记录原样保留。写回时用当前版本号
  （此前 writer 里硬编码 `schema_version: 1`，被新加的迁移测试抓出来）。
- 目录列表里的 `bytes` 必须走 **JSON 字符串**。第一版写成数字，控制面返回 200、内容也对，
  但控制台的 `Int64` 解码失败，于是"扫描模型库"永远报无法读取。现在有一条测试钉住这个线格式。

### 14.4 控制面：把受管模型库当制品服务

- 契约里新增 `modelstore://<store 相对路径>` 与 `lunanexa-source-manifest.json` 两个常量；
- `api/artifact_http.mbt` 的 `artifact_location()` 把 `s3://`（单对象）与 `modelstore://`（目录树）分开：
  目录树按**清单**授权——每次请求都读该 revision 的 `lunanexa-source-manifest.json`，
  校验其 SHA-256 等于 assignment 里签名过的 `artifact.digest`，再要求被请求的文件确实在清单里、
  且大小一致。清单之外的文件（例如 `stepfun35int4` 那 13 个 `.part-*`）**永远不会被送出**；
- 新增 `managed-revision` 校验种类：控制面用自己的模型库自查（清单摘要 + 每个文件存在且大小一致）
  来落 `ArtifactVerification`，`verifier` 记作 `modelstore-manifest:<uri>`。**这不是 cosign 签名**，
  是平台对自己存储的背书，所以字符串里写清楚是谁背的书；
- 认养门槛从"必须 `s3://`"放宽为"必须是控制面真正能服务的传输"，`signature_ref` 对目录树指向清单本身。

### 14.5 节点侧：把 revision 当目录树拉取

`node/artifact_materializer.mbt` 新增 `materialize_revision()`：

1. 先取清单，SHA-256 必须等于 assignment 的摘要（**清单就是签名**——目录树没有 detached cosign 签名，
   这一条要如实说明）；
2. 校验清单的形状（schema、model_id、非空、无重复路径），并校验清单里所有文件大小之和等于
   `artifact.size_bytes`；
3. 逐文件流式下载到 `sha256/<digest>.revision.partial/<path>`，支持断点续传，逐个比对 SHA-256，
   全部通过后整体 `rename` 成 `sha256/<digest>.revision` 并写 ready 标记；
4. 复用只重查"清单摘要 + 每个文件存在且大小一致"，不再重算 1.2 TB 的摘要（写进注释说明理由）。

`node/runtime_supervisor.mbt` 接受该 scheme：目录树挂载到 `/var/lib/lunanexa/model`，
`LUNANEXA_MODEL_PATH` 指向该目录；单对象制品保持原来的 `/var/lib/lunanexa/model/model` 文件挂载不变。

单测 `node/managed_revision_test.mbt` 用一个本地 HTTP server 覆盖：正常拉取、复用不重取、
清单被篡改、总大小与 assignment 不符，四种情况。

### 14.6 实测

- `moon check --target native --deny-warn` 通过（api / registry / ui / node / cmd.control /
  cmd.console / cmd.model-source / modelsource / contracts）；
- `moon test --target native --deny-warn`：`modelsource` 15/15、`node` 29/29、`ui` 70/70、
  `contracts` 5/5、`registry` 12/12；
- 通过浏览器（无头 CDP）在**控制台 UI** 上登记了全部五个目录，逐个点了 "Scan the model store" →
  选目录 → 填上游仓库 → "Register & verify"，返回提示
  *"Registration queued. The adapter re-derives every SHA-256 from ModelScope before the revision is verified."*；
- 登记是**逐文件重算 SHA-256**，管理节点顺序读盘实测 226 MB/s（四路并发约 480 MB/s），
  1.24 TB 全量校验约需 1.5 小时，五个 revision 由单 worker 顺序处理。

### 14.7 一个被真实数据抓出来的上游形态 bug

`deepseek-ai/DeepSeek-V4-Flash-DSpark` 第一次登记失败，错误码 `invalid-upstream-response`。
原因不是这个仓库特殊，而是**递归清单里目录也作为条目返回**：`encoding`、`encoding/tests`、
`inference` 三条 `Type=tree`、`Sha256=""`、`Size=0`，而 `legacy_file` 要求 64 位十六进制摘要，
于是一个子目录就否掉了整个 revision。之前只登记过没有子目录的仓库，所以一直没暴露。
现在在解码前跳过 `Type=tree`，并且"整份清单全是目录"仍然判为无效。修复部署后，
通过控制台的 **Retry** 按钮（不是后台命令）重新排队，返回 202 与
*"The import was requeued and will reuse verified partial files."*

### 14.8 登记列表只看到一层，漏了约 680 GiB

`local-directories` 原本只扫 `/data/models` 一层，且**跳过以 `.` 开头的目录**。而实际
checkpoint 大量存放在隐藏的 staging 目录里（`.spark-picture-20260916/models/...`、
`.new-models-20260915/models/...`）。于是下面这些**真实权重**在控制台里根本不存在：

| 目录 | 上游仓库 | 盘上 | 逐文件对齐 |
| --- | --- | --- | --- |
| `.spark-picture-phase2-20260916/models/LibertAIDAI/GLM-5.3-Flash-NVFP4` | `LibertAIDAI/GLM-5.3-Flash-NVFP4` | 181 GiB | 131/131 |
| `.spark-picture-20260916/models/Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw` | `Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw` | 164 GiB | 144/144 |
| `.spark-picture-20260916/models/RadixArk/Qwen3.8-Flash-Next-NVFP4` | `RadixArk/Qwen3.8-Flash-Next-NVFP4` | 126 GiB | 419/419 |
| `.spark-picture-20260916/models/Mia-AiLab/Qwen3.8-Flash-Next-NVFP4` | `Mia-AiLab/Qwen3.8-Flash-Next-NVFP4` | 99 GiB | 51/51 |
| `.new-models-20260915/models/Qwen/Qwen3-VL-32B-Instruct-FP8` | `Qwen/Qwen3-VL-32B-Instruct-FP8` | 33 GiB | 19/19 |
| `.new-models-20260915/models/Qwen/Qwen3.8-27B-FP8` | `Qwen/Qwen3.8-27B-FP8` | 29 GiB | 82/82 |
| `.spark-picture-20260916/models/unsloth/Qwen3.8-27B-NVFP4` | `unsloth/Qwen3.8-27B-NVFP4` | 22 GiB | 13/13 |
| `.spark-picture-20260916/models/RadixArk/Qwen3.8-27B-NVFP4` | `RadixArk/Qwen3.8-27B-NVFP4` | 20 GiB | 21/21 |
| `.spark-picture-20260916/models/z-lab/Qwen3.8-27B-DFlash2` | `z-lab/Qwen3.8-27B-DFlash2` | 3.6 GiB | 5/5 |
| `.spark-picture-20260916/models/incoai/GLM-5.3-Flash-DFlash2` | `incoai/GLM-5.3-Flash-DFlash2` | 2.2 GiB | 5/5 |

现在扫描会递归（深度 4）并报告"直接含模型入口"的目录：`config.json`、`model_index.json`
或 `*.gguf`。这样 diffusers / ComfyUI 那种把组件拆到子目录的布局会归到上层根，
而不会把 `vae/`、`text_encoder/` 当成独立版本。适配器自己的下载区（`models/modelscope`）
排除在外——它已经以导入的形式进平面了。

### 14.9 修复预算：命名错仓库不再等于"下载几百 GB"

改成两遍：第一遍整目录逐文件哈希并收集不一致项，第二遍只修复这些文件，
且**修复总量必须 < 该版本总量的 1% 或 1 GiB（取大者）**。理由是"某个 revision"本身就是
对这份目录的一个断言；差得太多就说明目录不是这个 revision，静默补齐可能从上拉几百 GB。
现在命名错仓库会以 `size-mismatch` 失败。

### 14.10 关于 "DeepSeek V4.1"

在 192.168.2.175 上**没有 V4.1 的权重**。全盘按名字和大小的排查结论：

- 唯一的 DeepSeek 权重目录是 `/data/models/deepseekv4flashdspark`，逐文件比对是
  `deepseek-ai/DeepSeek-V4-Flash-DSpark`（74/76 命中）；对
  `deepseek-ai/DeepSeek-V4.1-Flash` 比对为 17 缺失 / 71 大小不符，**明确不是 V4.1**。
- 与 V4.1 相关的只有两份**配方**压缩包（`/data/models/.spark-picture-20260916/sources/`，
  194 KB + 93 KB）：`MiaAI-Lab/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks` 与
  `sfxnz/DeepSeek-V4.1-Flash-EXL3-vLLM-2x-DGX-Spark`。它们是 README、补丁和量化脚本，
  其中的 README 引用的 196 GiB / 39 分片（`model-*-of-00048`）checkpoint 不在这台机器上。
- 四台 spark 的 `/var/lib/lunanexa-models` 里只有 `minimaxh3`；192.168.2.180 已下线。

### 14.11 统一布局：全部搬到 `/data/models/<owner>/<repo>`

规整之后每个模型在库里的 key **就是它的上游身份**，不再有 `minimaxh3`、`stepfun35int4`
这类自造缩写，也不再散落在隐藏 staging 目录里：

| 旧位置 | 新位置 |
| --- | --- |
| `minimaxh3` | `MiniMax/MiniMax-H3` |
| `stepfun` | `stepfun-ai/Step-3.5-Flash` |
| `stepfun35int4` | `stepfun-ai/Step-3.5-Flash-GGUF-Q4_K_S` |
| `deepseekv4flashdspark` | `deepseek-ai/DeepSeek-V4-Flash-DSpark` |
| `qwen3635ba3bfp8` | `Qwen/Qwen3.6-35B-A3B-FP8` |
| `.spark-picture-phase2-20260916/models/LibertAIDAI/GLM-5.3-Flash-NVFP4` | `LibertAIDAI/GLM-5.3-Flash-NVFP4` |
| `.spark-picture-20260916/models/Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw` | `Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw` |
| `.spark-picture-20260916/models/{RadixArk,Mia-AiLab}/Qwen3.8-Flash-Next-NVFP4` | `{RadixArk,Mia-AiLab}/Qwen3.8-Flash-Next-NVFP4` |
| `.spark-picture-20260916/models/{RadixArk,unsloth}/Qwen3.8-27B-NVFP4` | `{RadixArk,unsloth}/Qwen3.8-27B-NVFP4` |
| `.new-models-20260915/models/Qwen/Qwen3.8-27B-FP8` | `Qwen/Qwen3.8-27B-FP8` |
| `.new-models-20260915/models/Qwen/Qwen3-VL-32B-Instruct-FP8` | `Qwen/Qwen3-VL-32B-Instruct-FP8` |
| `.spark-picture-20260916/models/z-lab/Qwen3.8-27B-DFlash2` | `z-lab/Qwen3.8-27B-DFlash2` |
| `.spark-picture-20260916/models/incoai/GLM-5.3-Flash-DFlash2` | `incoai/GLM-5.3-Flash-DFlash2` |

15 个目录全部是同一文件系统内的 `mv`（rename），瞬时完成、可回退；
搬空后那三个 staging 的 `models/` 目录已删除。执行前确认过：没有任何活着的负载引用这些路径
（`comfyui-acceptance` 用的是它自己的 `/opt/ComfyUI/models`，`/data/models` 只是挂了个卷）。

顺序上必须先把平面停住，否则 worker 会读到被搬走的目录：

1. 先把 13 个在飞/排队的登记**通过 UI 逐个撤回**（含那个正在 Verifying 的——为此修了
   "verifying 不可取消"这个缺口）；
2. 再搬 + 改名；
3. 再**通过 UI** 重新登记 15 个。已 Verified 的两条记录因为目录已经不存在，按 14.12 的规则被替换。

### 14.12 搬完之后能重新登记：目录不在了就允许替换

`artifact_uri = modelstore://<store 相对路径>`，所以改名必然让旧记录指向一个不存在的路径，
而 `import_id` 只由 (model_id, revision) 决定，直接重登会撞 `ImportAlreadyExists`。
规则改为：**同名同版本允许替换，当且仅当旧记录指向的目录已经不存在**。理由是这个记录本来就
服务不了任何东西了；目录还在时仍然算重复、仍然拒绝。有单测覆盖"移动后重登成功、原地重登被拒"。

### 14.13 又一个上游形态问题：空的 per-file revision

`MiniMax/MiniMax-H3` 的每一条文件条目都返回 `Revision: ""`，而 `legacy_file` 要求它满足
`valid_revision`，于是整个 revision 被拒（`invalid-upstream-response`）。它的目录条目同样带
`Type: tree`、`Sha256: ""`。修法：per-file 的 revision 只是说明性字段（真正决定下载 URL 的是
tree 解析出来的那个 revision），空值放行，非空值仍必须合法。这条也补了单测。

### 14.14 节点 agent 上线（2026-09-20）

**构建在哪里**：不在管理节点，在 **spark .176** 上——`~/moon`（aarch64 MoonBit 工具链）
+ `~/src` + `~/pkg-node-image.sh`（把 `cmd/node` 的二进制加上 glibc/nvidia-smi/loopback
proxy 打成一个 OCI tar）。第一次构建失败在 `libpq headers are required`：spark 上没装 libpq。
家目录里有那两个 .deb，`dpkg-deb -x` 解到 `~/libpq-root` 再指 `C_INCLUDE_PATH`/`LIBRARY_PATH`
即可，**不需要 root、不改主机包状态**。

**产物**：`lunanexa-node:20260918-arm64-r4`，manifest `sha256:e8bab14b…`，config `sha256:7a8ad98c…`，
四台 spark 的 `imageID` 全部是 `7a8ad98c…`，即确实跑在 r4 上。

**踩到的三个坑**（都写在这里以免下次重踩）：

1. **tag 必须指向 manifest，不能指向 index。** `ctr images import --all-platforms`（在 x86 上
   不这样就报 "image might be filtered out"）会让 tag 落在 **OCI index** 上，CRI 于是既不认本地镜像、
   也不报错，表现是 kubelet 转去 `docker.io` 拉、`403`。正确做法是在 **arm64 节点上**
   plain `import`（默认平台过滤就会解析到 arm64 manifest），再
   `ctr images tag --force lunanexa-node:... docker.io/library/lunanexa-node:...`
   让两个名字都指向 manifest——和能用的 r3 记录形态一致。

2. **registry 路线被平台自己的 NetworkPolicy 挡住**，不该走。
   `lunanexa-registry-private` 的 ingress 只放行 `lunanexa` 命名空间的 `app=lunanexa-control`
   和带 `lunanexa.io/registry-client=true` 的 staging 命名空间；**节点 kubelet 不在白名单**。
   再加上 kubelet 在**节点**上解析 `.svc.cluster.local`（不走 CoreDNS，要 /etc/hosts），
   以及 spark→175 实测只有 6443 可达（15000 被拒），结论是：**spark 上的镜像只能本地导入**，
   这也正是现有每个 spark 镜像的来路。registry 仍然有用——离线导入流程和控制面用它。

3. **从 175 push 进 registry** 需要 `ctr images push --hosts-dir <dir>`：这个参数是
   **push 子命令**的（当全局参数会报 `flag provided but not defined`），`<dir>/<host>/hosts.toml`
   里 `ca` 指向 175 上那张 pinned leaf（`/etc/rancher/k3s/lunanexa-registry-pinned-leaf.crt`）。
   CA 本体在 `~/moon-public/trust/registry-20260830/registry-ca.crt`。

**副作用记录**：为了让 .179 试 registry 拉取，我改过它的 `registries.yaml` 和 `/etc/hosts`
并重启过一次 k3s-agent（该节点当时没有业务负载）。**其余三台没有做这些改动**，只是本地导入
+ 换镜像，因此没有重启过 k3s-agent，.176/.177 上的 minimaxh3 推理 pod 全程未受影响。

### 14.15 双机 GLM-5.3 Flash EXL3 跑通（2026-09-20）

**结果**：`.178`(rank0) + `.179`(rank1) 两台 DGX Spark 经 CX7 组成 TP=2，
vLLM 服务 `GLM-5.3-Flash-EXL3`，对外 URL：

```
GET  http://106.39.18.146:4174/glm53/v1/models
POST http://106.39.18.146:4174/glm53/v1/chat/completions
```

（走已有的 4174 前门，与 `/h3/`、`/h3r/` 同一套机制——见 14.16。）

**链路**：权重用配方 `Mia-AiLab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks`，镜像是
`ghcr.nju.edu.cn/miaai-lab/glm-5.3-flash-2x-dgx-sparks:exl3-e3-20260907`，
`NFS_SHARE=1`（只 head 存一份 164 GiB，worker 经 CX7 读 NFSv4）。

**测得的吞吐**（`max_tokens=256`，thinking off，含 DFlash2 投机解码）：

| 并发 | 请求数 | tokens | 墙钟 | 聚合 tok/s | p50 延迟 |
| --- | --- | --- | --- | --- | --- |
| 1 | 3 | 592 | 32.43 s | **18.25** | 10.88 s |
| 2 | 6 | 1117 | 42.52 s | **26.27** | 13.99 s |
| 4 | 12 | 2142 | 54.39 s | **39.38** | 17.31 s |

并发 4 是引擎的 `MAX_NUM_SEQS`，再高只会排队。扩展性是次线性的（1→4 只有 2.15×），
符合这个配方"低并发、长上下文"的定位。另测到单流在**高度可预测**提示上可达 55.6 tok/s
（"从 1 数到 60"），而叙述性提示只有 ~18 tok/s——**差异来自投机解码的接受率**，
不是引擎波动；报吞吐时必须连提示类型一起报。

**踩掉的十一个坑（按遇到顺序）**：

1. 镜像构建在 spark 上（`~/moon` + `~/pkg-node-image.sh`）；libpq 缺失用 `dpkg-deb -x` 解到
   `~/libpq-root`，不动主机包状态。
2. **spark 连不上 docker.io/ghcr.io/huggingface.co 直连，但国内镜像通**：
   ghcr → `ghcr.nju.edu.cn`（22 MiB/s，直连只有 95 KiB/s）；docker.io → `docker.m.daocloud.io`；
   HuggingFace → `HF_ENDPOINT=https://hf-mirror.com`。
3. `start.sh` 用**CX7 地址** ssh worker → head 的 `known_hosts` 要先 `ssh-keyscan`。
4. **不能在 `sudo` 下跑**：ssh 会忽略属主不是当前用户的私钥，于是"cannot ssh (key-based)"。
   正解是 `usermod -aG docker` + 普通用户运行。
5. 早先 sudo 运行留下的 `.env` 是 root 属主 → `chown -R`。
6. 配方会比较 **recipe stamp** 并默认重建镜像（重建要拉 docker.io）→ **`SKIP_BUILD=1`**。
7. **权重必须在 HF cache 标准命名下**：`hub/models--<owner>--<repo>/snapshots/<rev>/` + `refs/main`，
   而不是 `hub/<owner>/<repo>/snapshots/main/`。
8. 需要 `hf` CLI；PEP 668 拦用户安装 → `pip3 install --user --break-system-packages`。
9. 主权重用 `HF_HUB_OFFLINE=1`，但 DFlash2 draft 要先拉下来（2.2 GiB）。
10. NFS 导出容器**镜像缺 ENTRYPOINT**（`docker inspect` 显示 `entry=[]`、`cmd=[/bin/sh]`），
    容器起个 shell 就退出、退出码 0、日志空——极难猜；补 `ENTRYPOINT ["/entrypoint.sh"]` 解决。
    `apk add nfs-utils` 还要把源改到国内镜像；宿主 `nfsd` 模块要先 `modprobe`。
11. 配方把 `10.0.0.x` 判为 loopback，实际用 **`10.0.22.1`/`10.0.22.2`**；
    导出 ACL 本身正确，真正拦路的是 **worker 上缺 `alpine:latest`**——配方用它读 NFS 卷做校验，
    镜像缺失导致 pull 超时，却被报成 "cannot read … over NFS"（误导性报错）。
    另需 `chmod o+rx` 打开导出路径的目录穿越权限。

**脚本**（都在对应机器的家目录）：`pull-glm53.sh`、`export-glm53.sh`、`deliver-glm53-image.sh`、
`setup-cx7-ip.sh`、`switch-cx7-addr.sh`、`launch-glm53.sh`、`verify-glm53.sh`、`bench-glm53.py`。

### 14.16 对外暴露模型 API 的既有机制

前门是 `lunanexa` 命名空间的 `operator-4173-proxy`（nginx，`lunanexa-web` 镜像），
监听 `0.0.0.0:4174`，配置在 configmap `operator-4173-proxy` 的 `nginx.conf`：

```
location /h3/  { proxy_pass http://minimaxh3-fl2va:8000/;  proxy_read_timeout 7200s; ... }
location /h3r/ { proxy_pass http://minimaxh3-ref2va:8000/; ... }
location /glm53/ { proxy_pass http://192.168.2.178:8888/; ... }   # 本次新增
```

**注意它的滚动更新会卡住**：容器用 `hostPort`（4174/5000），新 pod 因端口被旧 pod 占用而
`Pending`，必须手工 `delete pod` 让新的接管（4174 会有十几秒中断）。以后改这个 configmap
都要按这个顺序做。

### 14.17 还没做的

- **ARM64 节点镜像没有重建/滚动**。节点侧代码已写、已测，但线上 4 台 spark 跑的还是
  `lunanexa-node:20260918-arm64-r3`，所以**现在没有任何 spark 真正用 revision 拉过模型**；
  "注册可用"目前止步于"已登记、已校验、控制面可服务、节点代码就绪"。
- 校验是单 worker 顺序执行的（见 14.6 的吞吐实测）。要做并发需要给进度累加器加锁并处理取消，
  这是明确可做的下一步，但本轮没有做。

---

## 15. MiniMax-H3 视频链路：四个缺陷（2026-09-21 晚）

链路是 ComfyUI（`aigc-acceptance-20260915/comfyui-acceptance`）→ 自研节点
`ComfyUI-vLLM-Omni` → `minimaxh3-fl2va`（.176）→ vLLM-Omni。一次 20 秒请求串出了四个
互相独立的缺陷。

**结论：20 秒视频已跑通**，产物 `LunaNexa20s_00001_.mp4`（4,519,434 B，
md5 `d8dbb9b1304cd077157da6f56be172e6`），由用户在 UI 上用 15.4 的模板触发，
不是脚本伪造的。四个缺陷里**服务端那一条已被证实修好**，客户端那两条**只装了、没被触发**，
画布进度**仍未解决**。分项依据见 15.5.1。

### 15.1 缺陷一：画布进度永远是 0%

`vllm_omni/diffusion/models/progress_bar.py` 里写的是 `config["disable"] = not _is_rank_zero()`，
而扩散 worker **不是 rank 0**，所以采样进度条被静默关掉；HTTP 侧的 `progress` 字段又只在
作业结束时才写一次（跑着时恒为 0，完成才变 100）。两头一夹，UI 上就只有 0%。

修法：补丁版 `progress_bar.py` 强制 `disable=False`，并让 `update()` 把
`{n,total,desc,updated_unix}` 写到 `/tmp/vllm_progress.json`。装入方式是新建 configmap
`minimaxh3-progress-patch`，给 `minimaxh3-fl2va` 加一个只读挂载 `/progress-patch`，并在
args 前面拼一句 `cp /progress-patch/progress_bar.py <site-packages>/.../progress_bar.py &&`。
原 sm121 补丁的 `cp ... && exec vllm serve ...` 一字未改。只改了 `fl2va`，**`ref2va` 没装**。

注意：这只是让**服务端**有真实进度。**ComfyUI 画布仍不会动**——`ComfyUI-vLLM-Omni` 里
`grep -i progress` 零匹配，节点根本没有上报代码。要让画布动，还得改
`serving_video.py` 把步数写进 job 的 `progress`，再让节点读出来。**这步没做。**

### 15.2 缺陷二：20 秒任务失败 —— 服务端编码 MP4 时堵死了自己的事件循环

这一节的根因判断当晚被我**自己推翻过一次**。两轮都留着，因为"错在哪里"本身是有用的记录。

#### 15.2.1 第一轮的判断：客户端 60 秒超时（不完整）

第一次 20 秒请求（608×352、481 帧、8 步，标记 `Sweep20s`）的时间线：

| 时刻 | 事件 | 来源 |
|---|---|---|
| 19:25:35 | 提交 | `/tmp/sweep.log` |
| 19:31:07 | 去噪 7/7 完成，5 分 32 秒、47.49 s/步 | pod 日志 |
| 19:32:39 | 服务端引擎结束 `total=424.24s stages=[0:424.24s]` | `stats.py:832` |
| 19:33:51 | 客户端 `Prompt executed in 496.26 seconds` + `RuntimeError` | ComfyUI pod 日志 |
| 19:34:22 | 服务端此时才把 MP4 编完：`Video response encoding (MP4 bytes): 102662.26 ms` | `serving_video.py:347` |

当时看到 `nodes.py:217` 的 `VLLMOmniClient(url, timeout=60, ...)` 经 `api_client.py:73`
变成 `aiohttp.ClientTimeout(total=60)`，`total` 覆盖整个请求**包括读 body**，于是判定
"下载被 60 秒预算掐死"。这个 60 秒预算确实是个真隐患，**但它不是杀人的那把刀**。

#### 15.2.2 更正：真正的根因在服务端

去掉客户端下载超时后重跑同一配置（标记 `Sweep20sFix`），**在同一个相对时刻又断了**：

| | 引擎结束 → 客户端断开 |
|---|---|
| 第一轮（有 60 秒下载预算） | 72 秒 |
| 第二轮（下载预算已去掉） | 75 秒 |

几乎一样。所以掐连接的东西和 60 秒无关，它绑定的是"引擎结束之后"。第二轮完整时间线：

| 时刻 | 事件 |
|---|---|
| 19:38:40 | 提交 |
| 19:45:51 | 去噪 7/7 完成，7 分 11 秒、61.58 s/步 |
| 19:47:56 | 引擎结束，`serving_time_to_first_output_ms = 555,846`（9 分 16 秒） |
| 19:49:11 | 客户端断开，`Prompt executed in 00:10:31`（631 秒） |
| 19:49:25 | **pod `Ready=False`** |
| — | 服务端**始终没有**打出 `Video response encoding` 这一行 |

`vllm_omni/entrypoints/openai/serving_video.py` 的 `async def generate_video_bytes` 里，
编码是**同步、CPU 密集**的，直接跑在事件循环上：

```python
video_bytes = _encode_video_bytes(artifacts.videos[0], fps=…, video_codec_options=…)
```

481 帧要编 **102.7 秒**。这 102 秒里整个 API server 什么都不响应。集群上的证据：

```
pod conditions:   Ready=False            lastTransition = 2026-09-21T11:49:25Z
event:            Readiness probe failed: Get "http://10.42.2.221:8000/health":
                  context deadline exceeded (Client.Timeout exceeded while awaiting headers)
kubectl get endpoints minimaxh3-fl2va   →   ENDPOINTS 为空
curl http://192.168.2.175:4174/h3/health →   502
```

**也就是说：每生成一个长视频，这个服务都会把自己的健康检查打挂、被踢出 Service、
对所有其他调用方返回 502。** 这不是"20 秒跑不了"的局部问题，而是这个服务在每次长任务
期间都会短暂失踪。`generate_videos`（base64 返回路径）有同一个毛病。

#### 15.2.3 仍未查清的一环：那 70 秒是谁掐的

诚实地记下来：pod 变 `Ready=False` 是在 **19:49:25**，比客户端断开（19:49:11）**晚 14 秒**，
所以"端点被摘掉"不是直接原因，两者是同一个原因（循环被堵）的两个后果。路径上量级对得上的
60 秒候选只剩一个：nginx 的 `send_timeout` 默认 **60 秒**（`/h3/` 只显式设了
`proxy_read_timeout` / `proxy_send_timeout`，没设它）。这一点**还没有被证实**，只把它
显式设成 7200s 作为待验证的假设，不当结论用。

### 15.3 修复

#### 15.3.1 服务端：把编码移出事件循环

`deploy/acceptance/patches/vllm-omni-h3/serving_video.py`
（md5 `914b4c058579b89d7792f811ce562d44`，原版 `97a324f58086ba4fceaa57ca6826e0d9`）改三处：

1. 顶部补 `import asyncio`。
2. `generate_video_bytes`：`video_bytes = await asyncio.to_thread(_encode_video_bytes, …)`。
3. `generate_videos`：把 base64 编码的列表推导改成显式循环 + `await asyncio.to_thread(...)`，
   语义不变，只是不再占着循环。

装入方式沿用 15.1 的 configmap + args 前缀 `cp` 通道（镜像里是 `/usr/local/lib/python3.12/
dist-packages/vllm_omni/…`，根文件系统只读，不能改镜像）。

#### 15.3.2 客户端：下载不吃控制面预算，且不销毁已完成的作业

`deploy/acceptance/patches/comfyui-vllm-omni/video_transport.py`
（md5 `e856e3c75d45bdfd55c9c5a983782487`，原版 `f247b36b0a430a416d3430eab36f64df`）改四处：

1. `download_timeout = aiohttp.ClientTimeout(total=None, sock_connect=30, sock_read=None)`，
   只给 `/content` 这一次 `session.get` 用；外层 `asyncio.timeout(max_poll_duration)` 仍然
   兜住整个作业，`max_wait_seconds` 的语义不变。
2. `/content` 下载失败**重试一次**（`_CONTENT_ATTEMPTS = 2`，间隔 5 秒）。重试会重新发起
   整个请求、服务端要再编码一遍，所以只给一次，并且仍然落在 `max_poll_duration` 之内。
3. 记 `completed` / `delivered` 两个标志。作业已经 `completed` 但字节没送到调用方时**不删**，
   只打一条 warning —— 删掉就等于销毁唯一一份成片。
4. `_failure_detail(data)`：把作业的 `error` 字段附在失败消息之后（见 15.3.4）。

文档字符串里写明了这几处是对上游传输层的 LunaNexa 偏离及其实测依据。

容器根文件系统是 `readOnlyRootFilesystem: true`，节点代码又烤在镜像里，所以用
**hostPath + subPath 盖单个文件**装进去，不动镜像：

```yaml
volumes:
- name: omni-video-transport-patch
  hostPath: {path: /data/comfyui-patches/omni-video-transport, type: Directory}
volumeMounts:
- name: omni-video-transport-patch
  mountPath: /opt/ComfyUI/custom_nodes/ComfyUI-vLLM-Omni/comfyui_vllm_omni/utils/video_transport.py
  subPath: video_transport.py
  readOnly: true
```

脚本：`deploy/acceptance/patch-comfyui-vllm-omni-node.sh`（幂等；ComfyUI 队列非空时**硬拒绝**
重启）。改 `deployment/comfyui-acceptance` 的 template 会按 `Recreate` 重建 pod，
备份在 `/tmp/comfyui-acceptance.backup-20260921.yaml`。容器内已核对 md5 与宿主一致。

#### 15.3.3 nginx：把 60 秒的默认值显式覆盖掉

`configmap/operator-4173-proxy` 的 `/h3/` 与 `/h3r/` 补 `proxy_connect_timeout 7200s;
send_timeout 7200s;`（原来只设了 `proxy_read_timeout` / `proxy_send_timeout`）。
**这是针对 15.2.3 那个未证实假设的对冲，不是已证实的修复**——真正的机制仍是待查的。
备份 `/tmp/operator-4173-proxy.backup-20260921.yaml`。
注意这个 nginx 用 `hostPort`，滚动更新会因端口占用卡住，**必须手工 `delete pod`**，
4174 会有十几秒中断。

改这个配置时踩了一个坑值得记下：幂等判断不能写成 `'send_timeout' not in line`，
因为 `proxy_send_timeout` **包含** `send_timeout` 子串，那样会 0 处命中。
要匹配带前导空格的 `' send_timeout'`。

#### 15.3.4 节点侧：fps 默认值，以及把服务端的错误透传出来

装上 15.3.1–15.3.3 之后，UI 上又失败了一次，这次是 **5 秒就死**，而且原因完全不同：

```
ERROR 12:09:50 [diffusion_worker.py:1316] ValueError: MiniMax H3 output fps is fixed at 24
  ← pipeline_minimax_h3.py:402, in _resolve_shape
→ RuntimeError: MiniMax H3 output fps is fixed at 24
→ POST /v1/videos  HTTP 500
```

两个独立的缺陷：

1. **`nodes.py:162` 把 `fps` 默认成 16，而 H3 只接受 24。** 也就是说
   **一个新画布在能跑之前就注定失败**——只要不去手动改那个格子。
   已改成 `default: 24`（`nodes.py`，md5 `37e7db584c2c35a55394537d99ee08b6`）。
   已核对：容器内 `grep '"fps"'` 显示 `default: 24`，且运行中的服务
   `GET /object_info/VLLMOmniGenerateVideo` 回报 `fps -> ['INT', {'default': 24, 'min': 1}]`。

2. **节点把服务端的错误正文丢掉了**，只留一句 `Video generation failed or its access ended`。
   于是"fps 必须是 24"这条极其明确的信息，到操作者眼里变成了一句无从下手的套话。
   已在 `video_transport.py` 里加 `_failure_detail(data)`：把 job 的 `error` 字段
   （字符串或 `{message|detail|error|reason}` 字典）折成单行、截到 200 字符，附在消息后面。
   这是**回给调用方**而不是记日志，所以不违反本模块"不记录提供方错误正文"的约定。

两个文件都由 `deploy/acceptance/patch-comfyui-vllm-omni-node.sh` 装（hostPath + subPath，
一份补丁目录带出两个文件）。写这个脚本时又踩到一个：**JSON patch 的 `add /-` 是追加**，
所以"每个模块加一次 volume"会在 `spec.volumes` 里产生两个同名条目、被 API server 拒；
现在 volume 只加一次，mount 逐个判断是否存在。

### 15.4 本轮的另一处改动：20 秒模板

`/data/models/comfyui-templates/lunanexa-h3/example_workflows/` 下新增
`LunaNexa MiniMax H3 - 20s 16x9.json`（由 5s 模板克隆而来）：608×352、**481 帧**、
24 fps、8 步、`generate_sound` 关、`max_wait_seconds` **1800**。

481 是 H3 自己的 20 秒值：`max(5, round(20×24)) + (5 − (480 mod 17)) % 17 = 480 + 1`。
帧数会被 H3 吸附到 17 帧栅格，所以要 481 而不是 480。

模板路由是**按请求读目录**的，加文件后不需要重启 ComfyUI：
`GET /api/workflow_templates` 立刻就能列出新名字。

### 15.5 实测速度（都是真数字，不是外推）

| 配置 | 时长 | 去噪 | 引擎合计 | 结果 |
|---|---|---|---|---|
| 384×256, 56 帧, 8 步 | 2.33 s | 5 s（7 步，0.74 s/步） | — | 41 s 出片 `LunaNexaQuick_00001_.mp4` 123,652 B |
| 608×352, 124 帧, 8 步 | 5.17 s | 54 s（7 步，7.76 s/步） | — | 111 s 出片 `Sweep5s_00001_.mp4` 499,289 B |
| 608×352, 124 帧（UI 那次） | 5.17 s | — | 72.72 s | 出片 `LunaNexa_00002_.mp4` 406,684 B |
| 608×352, 481 帧, 8 步（第一轮） | 20.04 s | 5 分 32 秒（47.49 s/步） | 424.24 s | 客户端断开；服务端 102.66 s 编完成片但已被删 |
| 608×352, 481 帧, 8 步（第二轮） | 20.04 s | 7 分 11 秒（61.58 s/步） | 555.85 s | 客户端断开；服务端编码未完成 |
| **608×352, 481 帧, 8 步（15.3 修完之后，UI 上跑的）** | **20.04 s** | **5 分 10 秒（7 步，48,285 ms/步）** | **386.28 s** | **成功出片 `LunaNexa20s_00001_.mp4`，4,519,434 B（md5 `d8dbb9b1304cd077157da6f56be172e6`）** |

（更正一处自己犯的错：我第一次量到这个产物报的是 2,883,632 B，那是我在 **12:19:0x** 采的样，
而文件直到 **12:20:24** 才写完。**列出文件大小之前要先确认它不再增长**——先看两次 md5 是否
一致，`ls` 的瞬时大小会把半成品当成成品。）

步数是 **7** 不是 8（`total = len(video_sigmas) - 1`）。
`denoise_step_latency_ms` 这一轮报 48,285.2 ms，和 tqdm 口径同量级。第三轮的引擎 386.28 s
比第二轮 555.85 s 快，**原因没有查清**（同样的模型、同样的分辨率与帧数），不编解释。

**一条重要的测量教训**：先前"25 帧 @512² 跑 95 分钟、约 120 s/步"的数据几乎全是冷启动的
`torch.compile` 区域编译成本（启动日志原话：lazy regional torch.compile with dynamic=True,
compilation errors may surface on the first request）。拿它外推会得出"20 秒不可能"的
错误结论。**预热之后同一个服务的每步耗时差一个数量级**，标度关系大致是 tokens^1.5
（tokens ≈ 帧数 × (W/32) × (H/32)）。

#### 15.5.1 修复到底有没有生效——分项结论，不许含糊

**服务端那一条（15.3.1）：已被证实。**

| | 修之前（第二轮） | 修之后（第三轮） |
|---|---|---|
| 编码期间 pod `Ready` | `Ready=False` lastTransition 11:49:25 | **`Ready=True`，lastTransition 停在 12:07:56 不动** |
| readiness 探针 | `Readiness probe failed: … context deadline exceeded` | **一条失败事件都没有** |
| `kubectl get endpoints` | 空 | `10.42.2.222:8000` 一直在 |
| 编码耗时 | 102.66 s（期间服务对所有人 502） | 49.21 s，期间 `/health` 正常应答 |

上一轮那个 pod 唯一的 `Unhealthy` 事件是**启动期**的 `Startup probe failed: connection
refused`（模型还没加载完，正常）。**没有一次 readiness 失败** —— 编码不再堵住事件循环。

**客户端那一条（15.3.2）：这一轮不能作数，如实说明。**
第三轮的编码只用了 **49.21 秒**，**低于**原来那 60 秒的预算——也就是说
**即使不打这个补丁，这一轮也不会被 60 秒超时掐死**。所以这次成功并不能证明
下载超时补丁是必需的。它的依据仍然是第一轮实测的 102.66 秒编码。同理，
`_CONTENT_ATTEMPTS = 2` 的重试这一轮**没有被触发过**，它是否有效仍未验证。

**15.2.3 那个约 70 秒的断开：仍然没有查清。** 三处改动之后它没有再出现，但有一次
编码只要 49 秒，说明不了问题；不能因为"这次没炸"就把它记为已解决。

### 15.6 本轮清理

`kubectl delete` 掉了 5 个命名空间里 `phase != Running/Succeeded` 的**终态残留 pod**
共 24 个（`aigc-acceptance-20260915`、`lunanexa`、`lunanexa-identity`、
`lunanexa-image-staging`、`lunanexa-build-staging`）：Error / ContainerStatusUnknown /
UnexpectedAdmissionError 这些哨兵。`lunanexa-identity` 的 CrashLoopBackOff 和
`dra-driver-nvidia-gpu` 的 Init:ImagePullBackOff **没动**——它们是还在反复重试的活故障，
属于另一条工作线，删 pod 只是重启一次同样的失败。

### 15.7 顺带修的：`progressDeadlineSeconds` 比真实启动时间短

两个 H3 deployment 的 `progressDeadlineSeconds` 都是 **600 秒**，而实测启动（加载 13 个
权重分片、再起 APIServer）要 **约 11 分钟**。后果是**每一次诚实的重启都会被报成一次失败的
rollout**：`kubectl rollout status` 直接以 `error: deployment "…" exceeded its progress
deadline` 退出（本轮 `fl2va` 就是这么报的，而它其实起得好好的——`grep -c asyncio.to_thread`
返回 3，补丁在位）。

已把两个 deployment 都改成 **1800**。这是 Deployment 的 spec 字段、**不在 pod template 里**，
所以改它不会触发重新调度，pod 年龄不变（改完仍是 11m、1/1 Running）。
`patch-vllm-omni-h3-encode.sh` 里也加上了这一步，免得下次重犯。

### 15.8 还没做的

- **15.2.3 那个约 70 秒的断开仍未查清。** 三处改动之后它没有再出现，但第三轮的编码只花了
  49 秒，说明不了问题。15.3.3 的 nginx 改动仍然只是对冲，不是已证实的修复。
- **15.3.2 的两条（下载不吃控制面预算、失败后重试一次）这一轮没有被触发。** 编码 49.21 s
  低于原来的 60 s 预算，`_CONTENT_ATTEMPTS` 也一次没用到。它们仍然只由第一轮实测的
  102.66 s 编码作依据，未被独立验证。
- **`_failure_detail` 的新错误文本只做了单元级验证。** 没有在真实的 HTTP 500 上走一遍——
  要确认它真能把 "MiniMax H3 output fps is fixed at 24" 送到 UI 上，得再故意用
  `fps≠24` 跑一次。
- 画布进度（15.1 末段）仍不通，这是**UI 上唯一还看得见的老问题**。
- `minimaxh3-ref2va` 装了编码补丁，但**没有**进度补丁。
- `UNETLoader` 是否列出两个 minimax diffusion 文件，未复核成功（解析脚本自身报错）。
- 排障时在 ComfyUI 队列里出现过非本人提交的任务 `b8dd1d07-…` 和 `5db096f3-…`，未追查
  来源；两个都正常完成了，产物分别是 `LunaNexa_00002_.mp4`（406,684 B）和
  `video_gen_7447526c405e4d5ba9ef279b0afd55.mp4`。
- 为让 ComfyUI 重扫权重而重启它时，队列里正有任务在跑。时间上错开了、未造成损失，
  但脚本打印了队列却没有据此中止——**重启前的队列检查要写成硬闸**（已在
  `patch-comfyui-vllm-omni-node.sh` 和 `patch-vllm-omni-h3-encode.sh` 里实现）。
- 排障用的脚本 `/tmp/sweep.sh`、`/tmp/sweep20fix.sh`、`/tmp/waitready.sh` 只在管理节点上，
  没有入库。
- 写这些脚本时踩到的另一类坑，记下免得重犯：**`sudo -S` 从 stdin 读密码**，所以
  `s kubectl create ... | s kubectl apply -f -` 永远失败（`error: no objects passed to
  apply`），必须把清单落临时文件再 `apply -f <file>`。
- 还有一个更阴的：本地那个 expect 包装脚本 `/tmp/luna_ssh.exp` 里写的是
  **`set timeout 30`**。它不是远端的命令超时，但效果一样——30 秒一到 expect 就往下走、
  脚本退出，ssh 被连带拆掉，命令死在半路。本轮因此两次把 `kubectl rollout status`
  和轮询循环掐断，报出来却像是远端失败。已改成 **`set timeout -1`**，并加了
  `ServerAliveInterval=30`。实测：45 秒和 100 秒的远端命令现在都能跑完。
  真正常驻/无人值守的活仍然该用 `setsid nohup … &`，那不是为了绕超时，而是为了不占着
  终端等。

---

## 16. 进度条为什么不动（2026-09-21 深夜）

### 16.1 诊断：不是坏了，是从来没接过线

三个断点，逐个有证据：

| 断点 | 证据 |
|---|---|
| worker 的步数 **→ 作业记录** | 全服务只有一处写 `progress`：`api_server.py:2892` 的 `"progress": 100`（和 `status: completed` 一起）。模型定义是 `protocol/videos.py:306` 的 `Field(default=0, ...)`，所以**跑的时候恒为 0**。步数本身存在：`diffusion/models/progress_bar.py` 的 `ProgressBarMixin`（注释："provides a progress bar for denoising loops"），但它的去处只有 worker 的 stdout，以及 LunaNexa 补丁额外写的 pod 内文件 `/tmp/vllm_progress.json`。 |
| 作业记录 **→ 节点** | 就算节点轮询 `GET /v1/videos/<id>`，读到的也是 0（见上一条）。那个 JSON 文件在 pod 里，HTTP 上看不见。 |
| 节点 **→ ComfyUI 界面** | 整个 `ComfyUI-vLLM-Omni` 里 `grep -rniE 'progress'` 只有一处命中，是 `video_transport.py` 判断作业**状态**用的 `status not in {"queued","in_progress"}`。没有任何 `ProgressBar` / `send_sync` / websocket 调用；`web/main.js` 共 21 行，注释写着 `// Stub frontend plugin for now`。 |

**澄清一句容易被误解的事**：15.1 那个 `progress_bar.py` 补丁让服务端有了真实步数，写进
pod 日志和 pod 内文件——那是**排障用的观测通道，不是 UI 功能**。对画布一点作用都没有。

### 16.2 三条线怎么补的

1. **服务端**（`patches/vllm-omni-h3/patch-api-server-progress.py`）：`retrieve_video` 在
   作业 `in_progress` 时，从步数文件算出百分比填进返回体。**只读，不动 store**——
   用 `model_copy` 出一份副本，因为 store 交出来的是共享对象，而 100 只能由完成路径写。
2. **节点传输层**（`video_transport.py`）：新增 `on_progress` 参数，每次状态轮询后调用。
   回调抛异常会被吞掉——**一个坏掉的 UI 钩子不能让一次已经付过钱的渲染失败**。
3. **节点**（`nodes.py`）：接到 `comfy.utils.ProgressBar` —— 这才是真正推动 ComfyUI
   进度条的东西（它发的是 websocket 的 `progress` 事件）。`comfy.utils` 是**延迟导入**的：
   它只在运行中的 ComfyUI 里存在，而这个模块也会被包自带的 `tests/` 导入。

`api_client.py` 也要跟着改：它的 `generate_video` 签名以 `**extra_body` 结尾，
**不显式声明的关键字会被当成表单字段 POST 出去**，所以 `on_progress` 必须写进签名。

### 16.3 为什么 `api_server.py` 用替换驱动而不是整文件补丁

它是 **3525 行 / 144 KB**。整文件入仓会把 144 KB 上游代码塞进仓库、把 20 行的改动埋进去。
所以这一处是**带断言的定位替换**：两个锚点各断言唯一命中、替换结果先 `compile()` 再落盘、
重复执行是 no-op。这个安全属性当场就生效过一次——第一版测试夹具我写歪了（漏了 FAILED
分支的函数体），驱动因为编译不过**拒绝写入**，没有留下半个坏文件。

### 16.4 已经核对的 / 还没验证的

**已核对**（容器内实测，不是推断）：

- 三个节点文件在容器内的 md5：`video_transport.py` = `e73c3aca5a9e2935503a06de379a0be7`、
  `api_client.py` = `cf0da9c6a31a872e306f407cdb07b56d`、`nodes.py` = `1634b018431fab00ae3af810ed9ad227`
- 节点装载正常，无导入错误；`fps` 默认仍是 24；`object_info` 正常返回
- 注入服务端的 `_live_video_progress` 用 9 个用例跑过：

  | 输入 | 返回 |
  |---|---|
  | `{n:3,total:7}` 文件新于作业 | `43` |
  | `{n:7,total:7}` | `99`（**封顶**） |
  | `{n:7,total:7}` 文件旧于作业 | `None`（不认） |
  | `{n:4,total:7}` 无 `updated_unix` | `57` |
  | `{}` / `total:0` / 非 JSON / 文件不存在 | `None` |
  | `{n:9,total:7}` | `99`（夹紧） |

**还没验证**：**没有在真实任务上看到画布动起来。** 服务端两个 pod 正在重启加载权重，
起来之后需要有人在 UI 上点一次 Run 才能确认端到端。

### 16.5 刻意的取舍，写清楚免得当成 bug

- **封顶 99，不封 100。** 去噪只有 7 步，之后还有 VAE 解码和 MP4 编码，服务端对这两段
  没有粒度。所以进度条会走完前约 5 分钟，然后在最后约 2.5 分钟停在 99 —— **这是真实的
  粒度上限**，不是卡住。100 留给"成片真的存在"。
- **步数文件是 pod 级单份的**，不带 request id。这个服务 `max_num_seqs=1`、单槽串行，
  所以不冲突；**一旦开并发必须改成按 request id 分开**，否则会串台。
- 一个自己的失误记在这：节点安装脚本第一版的 mount 循环**硬编码了文件名**，所以往
  `MODULES` 里加了 `api_client.py` 之后出现"暂存了、也校验了、但根本没挂载"——是校验
  循环把它抓出来的（脚本因此退出 1）。现在 mount 列表直接从 `MODULES` 推导。
