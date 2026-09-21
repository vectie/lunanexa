# 承诺函两侧对帐实测报告 — 2026-09-22

本次目标：企业侧与管理侧**同时**拉起，对承诺函（附件二 设备使用承诺函）链路做双侧对帐 ——
企业侧注册企业 → 选时间/租期 → 拉起承诺函 → 管理侧确认、执行 → 进入线下流程（默认通过）→
重新上传录入登记 → 开通权限 → 企业侧得到权限。要求：先测堵点卡点，记录**按下的每个按钮**，
检验每一步两侧的状态与进度显示是否正确、是否都有反馈。

## 结论摘要

1. **两侧默认入口都是 OIDC 登录门，而 OIDC 在本部署上原本整条是死的。** 两侧的登录链接
   `/auth/oidc/start?audience=…` 实测都返回
   `{"error":{"code":"NotFound","message":"route was not found","retryable":false}}`。
   根因是一条三跳链（见 §2.2）：身份库镜像引用名缺失 → Keycloak CrashLoopBackOff →
   `/auth/oidc/*` 既没接到身份网关、也没落在运维实际访问的端口上（见 §2.2 第 3 跳）。
   **本次已修好前两跳**（身份库 `1/1 Running`、Keycloak `1/1 Running`，Bootstrap completed），
   第三跳的端口拓扑仍是断的。
2. **管理侧可以进去，而且是实时数据**：控制台在 loopback 来源下提供「Local development token
   fallback」，填入部署自带的 operator/audit 令牌后控制台可用，显示 `4 of 4` 节点、`17` 个已批准模型。
3. **企业侧只能进到"外壳"**：用部署自带的推断令牌走「开发凭据后备方式」可以打开门户全导航，
   但会话是 `Organization setup · Not connected`，四类计数全 0。原因不是令牌错，而是控制面
   只信任来自 **loopback 对端**的 asserted subject（`api/server.mbt:5184-5198`），
   浏览器 → nginx → 控制面这条路径永远不满足。
4. **因此双侧对帐没有任何可对帐的物：** 管理侧 `Agreements 0`、`Leases 0`、
   `Contract documents — No contract packet yet`；企业侧连草稿订单都创建不出来。
5. 链路的**硬前提是"已批准订单"**，两侧各自的原话就是证据：管理侧
   「A packet is created from an approved order; no blank or invented contract is generated.」，
   企业侧「No eligible new order is available…」。而订单在 UI 上创建失败（§3.4）。
6. 另有 6 项状态/反馈缺陷（§4），其中演示模式的数字与控制面 **完全无关**（实测零网络请求）。

## 0. 方法与边界

- **业务流程全部在浏览器里点出来**（Chrome for Testing，CDP）。所有"按下的按钮"都是页面上
  真实可见控件的真实点击，操作前后都截图 + 抓取可见控件清单。
- **命令行只用于三件事**：读集群状态、读会话与路由所需的部署自带令牌、驱动浏览器。
  填入 UI 的令牌是从集群 secret 里取出再**键入 UI 自己的令牌输入框**（这正是控制台/门户
  自带的开发后备输入项），不是绕过 UI 直接打 API。
- 两侧各用独立标签页，避免一方登录把另一方会话冲掉。
- **未验证**：真实 OIDC 登录、真实订单提交、DOCX/PDF 生成、签署/盖章、扫描件上传、
  管理侧审批动作、权限实际开通、企业侧真正拿到权限。这些在前置条件不满足时无法进入。

## 1. 入口与勘误

| 侧 | 地址 | 实测 | 说明 |
|---|---|---|---|
| 企业侧 | `http://106.39.18.146:5002/enterprise/` | 200 | 标题「能源谷"创未来"街区算力平台 · Enterprise Portal」 |
| 管理侧 | `http://106.39.18.146:4174/console/` | 200 | 标题「…· Cluster Operations」 |
| 管理侧 | `http://106.39.18.146:4174/enterprise/` | **404** | 企业门户不在 4174 上；`/enterprise/` 属于另一个 server 块（监听 `127.0.0.1:5002`，`root /srv/portal`），该块 `/` 是 `302 /enterprise/?demo=1` |

第一个堵点是**入口没写清**：管理侧的 nginx 同一个端口上既服务控制台又"看起来"像服务门户，
但真正能打开企业门户的是 5002。

## 2. 会话：两侧各有一道门，而钥匙不存在

### 2.1 默认路径都指向不存在的路由（UI 实测）

| 页面 | 按下的链接 | 落地 URL | 结果 |
|---|---|---|---|
| 企业侧 5002 | `Sign in or create an account` | `/auth/oidc/start?audience=enterprise` | `{"error":{"code":"NotFound",…}}` |
| 管理侧 4174 | `Continue with organization sign-in` | `/auth/oidc/start?audience=operator` | `{"error":{"code":"NotFound",…}}` |

这个错误形状是**控制面**的 404（`api/server.mbt` 的 `api_error`），不是身份网关的形状
（网关对未知 `/auth/*` 返回扁平的 `{"error":"route-not-found"}`）。也就是说请求根本没有到
`lunanexa-identity-gateway`，而是落到了 `lunanexa-control`。

### 2.2 根因：一条三跳链（第 1、2 跳本次已修好并验证）

**第 1 跳 — 身份库没起来（镜像名缺失）→ 本次已修复**

原始状态：

```
statefulset/lunanexa-identity-postgres   READY 0/1   17d
  Warning ErrImageNeverPull  2m36s (x1207 over 4h22m)  kubelet
  Container image "docker.io/lunanexa/postgres:16-bookworm-bb3e1a57"
  is not present with pull policy of Never
```

关键证据：**同一个基础镜像以另一个名字已经在本地**。平台自己的主库
`pod/lunanexa-postgres-0`（`1/1 Running`）用的就是 `dockerproxy.net/library/postgres:16-bookworm`，
而身份库的清单（`/home/HwHiAiUser/moon-public/secure/platform-identity/identity-postgres.yaml:62-63`）
把它钉成了 `docker.io/lunanexa/postgres:16-bookworm-bb3e1a57` + `imagePullPolicy: Never`。
两者是同一份内容，只是名字不同 —— 属于"镜像按内容在、按引用名不在"这一类问题。

已执行（可加性、可回退，不影响任何运行中的工作负载）：

```sh
k3s ctr images tag dockerproxy.net/library/postgres:16-bookworm \
                   docker.io/lunanexa/postgres:16-bookworm-bb3e1a57
```

验证：两个引用指向**同一个 image id** `5f71c21b69a79`（155MB），随后

```
pod/lunanexa-identity-postgres-0   1/1  Running
  LOG:  starting PostgreSQL 16.15 (Debian 16.15-1.pgdg12+2) on x86_64-pc-linux-gnu …
  LOG:  database system was shut down at 2026-09-17 08:17:30 UTC
  LOG:  database system is ready to accept connections
```

**第 2 跳 — Keycloak 因此起不来 → 本次已修复并验证**

原始状态：

```
pod/lunanexa-platform-idp-0   0/1  CrashLoopBackOff  1106 (2m54s ago)  4d8h
pod/lunanexa-platform-idp-1   0/1  CrashLoopBackOff  1105 (3m50s ago)  4d8h
  ERROR: Failed to start server in (production) mode
  Error details: Failed to obtain JDBC connection
  causedBy: java.net.UnknownHostException:
            lunanexa-identity-postgres.lunanexa-identity.svc.cluster.local
```

（Keycloak/Quarkus 自身一直是正常的 —— `Keycloak 26.7.3 on JVM … started in 6.530s`，
它是在 `checkUtf8Encoding` 连库那一步挂掉的，所以库一好就能起来。）

库好了之后删掉两个 IdP pod 让它立刻重试，结果：

```
pod/lunanexa-platform-idp-0   1/1  Running   0   75s
  "Bootstrap completed in 3.761000 seconds"
  "ISPN000094: Received new cluster view for channel ISPN … (1) […]"
pod/lunanexa-platform-idp-1   0/1  Running   (启动中，正在加入集群)
```

**第 3 跳 — `/auth/oidc/*` 没接到身份网关 → 仍未修**

`lunanexa-identity-gateway` 本身是**好的**（`2/2 Running`，ClusterIP `10.43.50.102:8081`），
`lunanexa-identity-relay` 也在。挂掉的是边缘（同一个"引用名缺失"病）和前端路由：

```
deployment/lunanexa-identity-edge            0/2  CreateContainerError
deployment/lunanexa-identity-internal-edge   0/2  要 …/moon/lunanexa-web@sha256:a6136238fb0d…
deployment/lunanexa-identity-public-edge     0/1  要 lunanexa/web:management-20260827-console-compat-10
                                                  → ErrImageNeverPull（policy: Never）
deployment/lunanexa-enterprise               0/1  CreateContainerError
deployment/lunanexa-workbench                0/1  CreateContainerError
```

**第 3 跳其实有两个子问题，第二个更要命：OIDC 配置的端口和你在用的端口不是同一批。**

身份网关的配置（configmap `lunanexa-identity-ingress-config`，`LUNANEXA_IDENTITY_GATEWAY_MODE=proxy`）
把它自己钉在下面这套公开拓扑上：

| 配置项 | 值 | 实测 |
|---|---|---|
| `LUNANEXA_OIDC_ISSUER_URL` | `http://106.39.18.146:5006/realms/lunanexa` | **5006 → 000（不通）** |
| `LUNANEXA_IDENTITY_CANONICAL_ISSUER` | `https://106.39.18.146:5006/realms/lunanexa` | 同上 |
| `LUNANEXA_OIDC_OPERATOR_REDIRECT_URI` | `http://106.39.18.146:**5003**/auth/oidc/callback` | **5003 → 000（不通）** |
| `LUNANEXA_OIDC_ENTERPRISE_REDIRECT_URI` | `http://106.39.18.146:**5005**/auth/oidc/callback` | 5005 → 200（但不由身份边缘提供） |
| `LUNANEXA_PUBLIC_HTTP_ENABLED` | `true` | — |

而实际在用的两个端口是 **4174（控制台）** 和 **5002（企业门户）**，它们**没有 `/auth/*` 路由**：

```
4174/auth/oidc/start?audience=operator -> {"error":{"code":"NotFound",…}}
5002/auth/oidc/start?audience=operator -> {"error":{"code":"NotFound",…}}
5003/auth/oidc/start?audience=operator -> (空，端口不通)
5006/auth/oidc/start?audience=operator -> (空，端口不通)
```

后端为什么是空的也查清了 —— 两个 LB 的 Endpoints 都是空的：

```
svc/lunanexa-console-public   (5003)  selector app=lunanexa-identity-edge        ENDPOINTS: (空)
svc/lunanexa-identity-public  (5006)  selector app=lunanexa-identity-public-edge ENDPOINTS: (空)
```

即：**5003 由 `lunanexa-identity-edge`（0/2）提供，5006 由 `lunanexa-identity-public-edge`（0/1）
提供，两个都在镜像问题上躺着。** 于是 OIDC 登录的公开拓扑整体是死的，而用户手上那两个
端口（4174/5002）从来没被给过 `/auth/oidc` 路由。这是"点了登录链接就 404"的完整答案。

修法（两件都要做）：① 让两个 edge 的镜像引用可解析并重滚；
② 把 `/auth/oidc/*` 与 `/auth/session` 接到 `lunanexa-identity-gateway:8081`，
并且让重定向 URI（5003/5005）与运维实际访问的端口对齐 —— 否则登录回来仍会落到别的 origin。

### 2.3 实际能用的进入方式（本次实测所用）

**管理侧 — 成功。** 关键点：控制台的开发后备**只在 loopback 来源下出现**。通过
`http://127.0.0.1:4174/console/` 打开时，页面出现：

```
Local development token fallback
（字段：login-operator-token、login-audit-token）
```

填入部署自带的 `LUNANEXA_OPERATOR_TOKEN` / `LUNANEXA_AUDIT_TOKEN`（来自 secret
`lunanexa-control-credentials`）后按钮由灰变亮，点击进入。进入后横幅：

```
Local fallback active
Controller connection  http://127.0.0.1:4174
```

并且是**实时数据**：`Node availability 4 of 4`、`Serving models 17`、`Pending queue 0`、
`Open alerts 0`。

**企业侧 — 只到外壳。** 门户的开发后备字段是 `portal-token`（"Scoped development token"）、
`portal-subject`（"Opaque test subject"）、`portal-endpoint`，按钮 "Connect development identity"。
填入部署自带的 `LUNANEXA_INFERENCE_TOKEN`（`api/portal_http.mbt:144` 的 `portal_subject`
确实接受它对 `bearer_authorized` 分支）后门户打开全导航，但会话条是：

```
Organization setup · secure browser session; ends on logout or expiry
Not connected · Tenant scoped
Agreements to review 0 · Open lease requests 0 · Models entitled 0 · Current spend —
```

### 2.4 为什么企业侧"填对令牌也只能到外壳"（架构性）

`api/workspace_http.mbt:8-34` 的 `trusted_workspace_subject` 要先过一道总闸：

```moonbit
if !allow_asserted_subject {
  return None
}
```

而 `api/server.mbt:5184-5198`：

```moonbit
fn loopback_client(address : @socket.Addr) -> Bool { … has_prefix("127.") … }
…
let allow_asserted_subject = loopback_client(connection.client_addr())
```

`api/server.mbt:5126-5131` 的注释点明了原因：`moonbitlang/async 0.20.3` 的
`connection.client_addr()` 目前给出的是**被接受套接字的本地地址**而不是对端地址，所以
受信的身份变更被单独放到一个 loopback 监听器上（`serve_identity_on`）。

推论：**浏览器 → nginx → 控制面 ClusterIP 这条路径的对端永远不是 loopback**，
所以门户的开发后备在结构上就拿不到租户主体。生产路径必须走 identity 边缘/relay 的 mTLS
（`ssl-client-verify: SUCCESS` + `ssl-client-subject-dn`），而那条路现在是 `0/1`。

## 3. 复现步骤表：按下的按钮 → 两侧看到什么 → 是否有反馈

| # | 侧 | 按下的控件 | 结果原文 | 反馈 |
|---|---|---|---|---|
| 1 | 企业侧 | 链接 `Sign in or create an account` | `/auth/oidc/start?audience=enterprise` → `{"error":{"code":"NotFound",…}}` | 有，但是死路 |
| 2 | 管理侧 | 链接 `Continue with organization sign-in` | `/auth/oidc/start?audience=operator` → 同上 | 同上 |
| 3 | 管理侧 | 开发后备：填 `login-operator-token`、`login-audit-token` → 提交按钮 | 控制台进入，`Local fallback active` | 有，正确 |
| 4 | 企业侧 | 开发后备：填 `portal-token` → `Connect development identity` | 门户打开，`Organization setup · Not connected` | 有，但状态为未连接 |
| 5 | 企业侧 | 导航 `Orders & documents` | 显示 "Configure a new order"（`offline-project` / `offline-service` / `offline-sla`） | 有 |
| 6 | 企业侧 | 填三项后按 **`Create draft order`** | `Operation: The action failed. Refresh and retry; if it persists, contact your operator with the action and time. Sensitive technical details are hidden.`；订单仍未创建（`No commercial orders yet`） | 有，但不可诊断 |
| 7 | 企业侧 | 导航 `Get started` | 出现 6 步向导：1 Service / 2 Organization / 3 Capacity / 4 Quote / 5 Contract & payment / 6 Provisioning，以及三张服务卡 | 有 |
| 8 | 企业侧 | **`Choose this service`**（Shared MaaS 卡） | 进入 "Shared MaaS · Start with the shared API"，按钮 `Create API key` | 有 |
| 9 | 企业侧 | **`Create API key`** | 跳到 `Account & API keys`，显示 **`Account identity is unavailable.`** | 有，正确且清楚 |
| 10 | 企业侧 | 导航 `Contract forms` | `Contract packet — No matching contract.` / **`Contract template unavailable — The verified template manifest must load before information can be collected.`** / `Operation: The action failed…` | 有，但模板都加载不到 |
| 11 | 企业侧 | 导航 `Agreements` | `Agreements requiring your organization` → **0** | 有 |
| 12 | 管理侧 | 导航 `Agreements` | `0 agreements` · `No agreement evidence is loaded.` · `No enterprise lease requests are waiting.` | 有，实时 |
| 13 | 管理侧 | 导航 `Leases` | `0 machines leased · 0 workspace leases` · `No exclusive machine leases are recorded.` | 有，实时 |
| 14 | 管理侧 | 导航 `Offline commerce` | 渲染权威状态图：Draft → Quoted → PendingInternalApproval → PendingOfflineExecution → PendingEvidenceUpload → UnderReconciliation → FulfillmentPending → Fulfilled（另有 correction loop 与 terminal exit）；`SELECTED ORDER — No order selected` | 有 |
| 15 | 管理侧 | 导航 `Contract documents` | `TASK INBOX` 0 approvals / 0 overdue / 0 closure proposals；**`No contract packet yet — A packet is created from an approved order; no blank or invented contract is generated.`**；Effective contracts 0；Ledger amount `CNY 0.00` | 有，实时 |

**关键交叉印证**：#6 企业侧建不出订单，#15 管理侧说"订单批准才生成包"，#12/#13/#14 管理侧
三个对帐队列全空。**链路在第一步（订单）就断了，两侧因此没有共同的对帐物。**

## 4. 每一步的状态/进度显示是否正确、是否有反馈

做得**对**的部分：

- 管理侧各页的空态是诚实且可操作的，不是空表格：`No agreement evidence is loaded.`、
  `No contract packet yet — …no blank or invented contract is generated.`、
  `No exclusive machine leases are recorded.`。
- `Account identity is unavailable.` 这条反馈是准确的（相对于模糊的失败，它直接点名缺身份）。
- 权威状态图（Offline commerce）把 happy path、correction loop、terminal exit 都画出来了，
  这是"进度显示"应有的样子。

发现的问题：

1. **同屏三处状态互相矛盾**（企业侧 Contract forms，夹具路径下实测）：
   下拉框读出 `Ready to review`，同一页 CONTRACT STATUS 写 `No approval is currently waiting.`，
   时间线写 `No authoritative lifecycle events are loaded yet.` —— 三个状态源没有共同真相。
2. **可访问名丢失**：落地页三张卡片的无障碍名字**完全相同**（都是 `Choose this service`），
   从标签、读屏都分不出是哪张卡。建议带上服务名（如 `Choose Shared MaaS`）。
3. **`Required` 标签与实际状态不符**：标签写 Required 的输入框里已经有值，
   无法区分"必填但为空"和"必填且已满足"。
4. **错误过于不透明**：`Sensitive technical details are hidden.` 之后没有错误码、没有关联 id、
   没有指向"账户身份不可用"的提示。用户与运维都无法从界面判断该找谁做什么。
   （对比 #9 的 `Account identity is unavailable.` 就是好例子。）
5. **演示模式的数据与控制面无关，且未在应用内标明来源**：`?demo=1` 渲染
   `DEMO · enterprise portal`、租户 `org-northstar`、`Agreements to review 1`、
   `Open lease requests 1`、`Models entitled 2`、`Current spend CNY 18,420.00`。
   实测该页面非静态资源类网络请求为 **0 条**
   （`performance.getEntriesByType('resource')` 过滤掉 js/css/png/woff 后为 `[]`）。
   同一时刻管理侧读到的是 0 / 0 / 0 与 `CNY 0.00`。早前该路径的文案也自认
   `Demo information saved locally; no controller was contacted.`
   —— 这些数字是本地夹具，**不能当作对帐依据**。
6. **会话范围标签语义不一致**：企业侧有 `Organization setup`（无成员关系）、
   `org-northstar · Tenant scoped`（演示）、管理侧另有 `Local fallback active`。
   同一个"已登录"在两侧含义不同，页面上没有统一解释。

## 5. 卡点清单（按修复收益 / 代价排序）

1. ~~**补 `docker.io/lunanexa/postgres:16-bookworm-bb3e1a57` 到 containerd 并让身份库起来。**~~
   **✅ 本次已完成并验证。** 该镜像内容早已在本地（`dockerproxy.net/library/postgres:16-bookworm`，
   主库 `lunanexa-postgres-0` 正用着），只是引用名不同；`k3s ctr images tag` 加别名即可
   （同一 image id `5f71c21b69a79`）。身份库 `1/1 Running`，Keycloak `1/1 Running`。
   教训：`imagePullPolicy: Never` 下，**引用名必须精确匹配**，内容相同不算。
2. **让两个 edge 的镜像引用可解析并重滚**（第 3 跳的前半）。
   `lunanexa-identity-edge` 要 `…/moon/lunanexa-web@sha256:a6136238fb0d…`（当前报
   `CreateContainerError`，它去解析 `sha256:4932e4461c098…` 时找不到）；
   `lunanexa-identity-public-edge` 要 `lunanexa/web:management-20260827-console-compat-10`
   （`ErrImageNeverPull`）。这与第 1 条同一病因，但**必须先确认哪个本地镜像才是这两个引用
   对应的构建**，不能像 postgres 那样只凭"同名基础镜像"就下判断。
   注意 `lunanexa-identity-console-public` / `lunanexa-identity-public` 两个 LB 的 Endpoints
   现在是空的，就是被这两个 deployment 拖空的。
3. **把 `/auth/oidc/*` 接到 `lunanexa-identity-gateway:8081`，并让端口对齐**（第 3 跳的后半）。
   网关的 redirect URI 配的是 5003（operator）/ 5005（enterprise），issuer 在 5006，
   而运维实际访问的是 4174 / 5002 —— 这几套端口必须先统一，否则登录回来会落到别的 origin。
   目前 4174/5002 上的 `/auth/oidc/start` 直接穿透到控制面，所以报的是控制面的 404 形状。
4. **Keycloak 确认 realm 与客户端**：`keycloakrealmimport/lunanexa-public-bootstrap-v1`
   已经 `Completed`，`keycloak/lunanexa-platform-idp` 现已 `1/1 Running`；网关侧
   `LUNANEXA_OIDC_OPERATOR_CLIENT_ID=lunanexa-operator`、`…_ENTERPRISE_CLIENT_ID=lunanexa-enterprise`
   与密钥都已注入，下一步要验证 5006 上的 discovery 真能应答。
5. **让企业侧拿到租户主体**。要么走 identity 边缘的 mTLS（`lunanexa-identity-*` 系列先修起来），
   要么接受"开发后备在结构上无法建立租户主体"这一事实并在 UI 上说清楚
   （现在是 `Not connected` + 一个不透明的 `The action failed.`）。
6. **给订单一条真实可用的创建路径**。这是整条承诺函链的硬前提，两侧的原话都指向它。
7. **统一状态源**：企业侧同一页的三个状态读数必须来自同一份生命周期事实。

## 6. 要跑通承诺函链路，还缺什么

按目标里的每一步标注本次实测到哪：

| 目标步骤 | 本次实测状态 | 缺什么 |
|---|---|---|
| 企业侧注册企业 | **未达** | OIDC（第 1-3 跳）；`Organization setup` 无成员关系 |
| 选择时间、租期 | **未达** | 向导存在（6 步），但需先有身份；租期价格表在承诺函附件一中（日 85 / 周 520 / 月 1900 / 季 5100 / 年 15800，招商：首单周 349、首单月 8 折 1520、季租及以上 7.5 折） |
| 拉起承诺函 | **未达（堵在订单）** | 模板清单加载不到（`Contract template unavailable`）；且**没有合格订单**，`Prepare document` 不可用 |
| 管理侧确认 | **未达（无物可确认）** | 管理侧 `Agreements 0`、`Leases 0`、`Task inbox 0` |
| 进入线下流程（默认通过） | **未达** | Offline commerce 的状态图在，`No order selected` |
| 重新上传录入登记 | **未达** | Contract documents 在，`No contract packet yet` |
| 开通权限 | **未达** | 企业侧 `Create API key` → `Account identity is unavailable.` |
| 企业侧得到权限 | **未达** | 同上；权限授予依赖身份与订单 |

## 7. 本次实测确实验证了的东西

- 两侧入口、以及 4174 上 `/enterprise/` 是 404 这个勘误。
- 两侧默认 OIDC 入口在本部署上是 404（UI 点击级证据 + 控制面错误形状判定）。
- 三跳根因链的每一跳（集群对象、事件、日志原文都在 §2.2）。
- **第 1、2 跳确实修好了**：`k3s ctr images tag` 加别名后身份库 `1/1 Running`
  （`database system is ready to accept connections`），Keycloak `1/1 Running`
  （`Bootstrap completed in 3.761000 seconds`）。修法与验证都在 §2.2。
- **第 3 跳的两半都定位到了**：两个 edge 的精确镜像引用（附各自的失败原因），
  以及 OIDC 配置端口（5003/5005/5006）与运维在用端口（4174/5002）不一致，
  并且 5003/5006 对应的 LB Endpoints 是空的。
- 管理侧可以用部署自带令牌经控制台自带的开发后备进入，且显示实时集群数据。
- 企业侧填对令牌也只能到 `Not connected` 外壳，且原因是 `loopback_client` 总闸（代码级证据）。
- 链路在"订单"这一步断掉，两侧因此没有共同对帐物（两侧原文互相印证）。
- 演示模式数字与控制面无关（零网络请求实测）。
- 六项状态/反馈缺陷。

## 8. 未验证

- 真实 OIDC 登录与首次登录建账户/受限体验。
- 真实订单提交、管理侧审批、DOCX/PDF 生成与下载、签署盖章、扫描件上传与复核。
- 权限实际开通后企业侧是否真正拿到权限。
- 管理侧的 CPU/内存等指标在浏览器中的渲染（本次控制台是实时数据，但没有逐项核对指标卡）。

本次对帐的记账口径：**"能点进去并拿到实时数据"才算一步通了**；只有页面渲染、数据来自
本地夹具或本地会话的，不计为通。
