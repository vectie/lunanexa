# 承诺函两侧对帐实测报告 — 2026-09-22

本次目标：企业侧与管理侧**同时**拉起，对承诺函（附件二 设备使用承诺函）链路做双侧对帐 ——
企业侧注册企业 → 选时间/租期 → 拉起承诺函 → 管理侧确认、执行 → 进入线下流程（默认通过）→
重新上传录入登记 → 开通权限 → 企业侧得到权限。要求：先测堵点卡点，记录**按下的每个按钮**，
检验每一步两侧的状态与进度显示是否正确、是否都有反馈。

## 结论摘要（截至最后一轮的实际情况）

> 这一节在过程中被改写多次；**下面是最终状态**。中间那些已经修掉的结论不再保留在此，
> 但每一次定位与更正的证据都留在 §2.x 的流水里（包括两处我先写错、随后自己更正的记录）。

### 一、链路现在走到哪

| 目标步骤 | 现状 |
|---|---|
| 企业侧注册企业 | **通** —— 组织从已登录身份自动派生（首次 OIDC 登录建的受限试用组织），无需填表（§9.1） |
| 选择时间、租期 | **部分** —— 页面可达、**机器可选**（`Available`）、区域可选、时长 1 小时 ~ 30 天可选；卡在 `Review price`（§9.8、§9.9）。价目见 §10 |
| 拉起承诺函 | **未达** —— 承诺函由"已批准订单"生成，还没有订单 |
| 管理侧确认、执行 | **未达** —— 管理侧 `Agreements 0`、`Leases 0`、契约任务箱 0（§3 表） |
| 线下流程 / 上传登记 / 开通权限 | **未达** —— 对应页面在（Offline commerce、Contract documents），无数据可操作 |
| 企业侧得到权限 | **部分** —— 管理侧用 GUIDED SETUP 给该账户建好了账户/成员/工作区/Developer 授权（`Ready`，§9.4），但**租赁类权限**没有 |

**一句话**：链路已经**走过容量格、到了报价前一步**；再往前需要解决 `Review price`
那一跳，以及真正产生一张订单。

### 二、两侧数据面已经是可信的（这是能走链路的前提）

这一路修掉的东西，按重要性排：

1. **身份栈整条是死的** → 全部修通：身份库、Keycloak、身份边缘、
   缺失的 `identity-relay` 旁车（从仓库既有清单补回）、网关的 OIDC 路由与端口对齐。
   现在两侧都能完成**真实 OIDC 登录**（§2.2、§2.6）。
2. **网关把一个 int64 发成 JSON 数字**，而 JS 后端的 `Int64::from_json` 只收字符串
   → 两侧前端**登录成功后都解不出会话**、回落登录门。改成字符串并**重建重滚镜像**后修复（§2.7、§2.13）。
3. **前门无条件覆盖 `Authorization`**，把浏览器的 `lnxs_` 会话冲掉
   → 会话类接口全 401/403。改成"带了就用、没带才回落静态令牌"（§2.9）。
4. **生产侧把 `Option` 序列化成数组**（`Some(x)` → `[x]`），控制台按标量解 → 整块访问读取回落空态
   → 管理侧把 12 个用户 / 16 条授权显示成 `0 users · 0 grants`。修复并重滚控制面后，
   管理侧显示 `12 users · 16 grants`、`Registered trials 1`（§2.13、§2.15）。
5. **登录后被无条件送进 demo 门户** → 改成按会话 cookie 分流，登录后直接落在真实门户（§2.16）。
6. **控制台的测试在 HEAD 上编不过**（辅助函数签名漂移）→ 修好后 61/61（§2.13）。

### 三、现在真正挡路的，只剩这几条

| # | 卡点 | 证据 | 归属 |
|---|---|---|---|
| 1 | `Review price` 点击**无请求、无反馈** | 合成点击与**真实鼠标事件**都不产生 `/v1/` 流量（§9.9） | **待真人点一次定论**；但"无效时零反馈"这条缺陷**已可确认** |
| 2 | 供给侧**没有界面** | 源码与线上 bundle 里 `machine-commerce` 均 0 引用（§9.5） | 产品缺口（本次用 API 代发，已标注偏离） |
| 3 | 节点原本**没有 `lunanexa.io/region`**，可用容量恒为 0 | 四台节点标签 + 判据 fail-closed（§9.7） | **已修**（补标签 + 对齐供给参数） |
| 4 | 无订单 ⇒ 无承诺函 | 管理侧原话 "a packet is created from an approved order" | 依赖 1 |

### 四、需要你决定的事

1. **公网明文登录开关**：控制台按设计拒绝在公网明文下登录；要么装 TLS，要么显式打开
   `lunanexa-public-http-origin` 那一个 meta（明文有中间人风险）。**未替你按**。
2. **前端那个静态操作员令牌**：现在只作为"没带凭据时的回落"，但仍明文写在 ConfigMap 里，
   4174/5002 无需登录即可调用操作员 API。**去留由你定**。
3. **`Review price` 请人工点一次**：这是我这边无法定论的唯一一环。

### 五、如实标注的偏离与不确定

- 为了让链路能动，有**两处供给动作是在界面之外做的**（发布 offering、给节点补 region 标签）。
  这**不符合"纯 UI"的要求**，但管理侧确实没有对应界面（§9.5）。
- 报告里有两处**我先写错、随后自己更正**的记录：一处是把裸 fetch 的 403 当成会话问题（§9.2），
  一处是把它当成"没有购机角色"（§9.7 之前）。两处的更正过程都留在正文里。
- `Create draft order` 与 `Review price` 两个按钮的"点了没反应"，
  在代码上都能找到**静默分支**的解释，但**都没有用真人点击最终确认**。

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

## 2. 会话：从整条死掉，到两侧都能真实登录（过程记录）

> 本节按时间顺序保留每一次定位与更正；**最终状态见开头「结论摘要」**。

### 2.1 默认路径都指向不存在的路由（UI 实测）

| 页面 | 按下的链接 | 落地 URL | 结果 |
|---|---|---|---|
| 企业侧 5002 | `Sign in or create an account` | `/auth/oidc/start?audience=enterprise` | `{"error":{"code":"NotFound",…}}` |
| 管理侧 4174 | `Continue with organization sign-in` | `/auth/oidc/start?audience=operator` | `{"error":{"code":"NotFound",…}}` |

这个错误形状是**控制面**的 404（`api/server.mbt` 的 `api_error`），不是身份网关的形状
（网关对未知 `/auth/*` 返回扁平的 `{"error":"route-not-found"}`）。也就是说请求根本没有到
`lunanexa-identity-gateway`，而是落到了 `lunanexa-control`。

### 2.2 根因：一条三跳链（本次已修复并逐跳验证，详见 §5）

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

**第 3 跳 — `/auth/oidc/*` 没接到身份网关 → 前半已修复，后半还剩一个策略开关**

`lunanexa-identity-gateway` 本身是**好的**（`2/2 Running`，ClusterIP `10.43.50.102:8081`），
`lunanexa-identity-relay` 也在。挂掉的是边缘（同一个"引用名缺失"病）和前端路由：

```
（修复前）
deployment/lunanexa-identity-edge            0/2  CreateContainerError
deployment/lunanexa-identity-internal-edge   0/2  要 …/moon/lunanexa-web@sha256:a6136238fb0d…
deployment/lunanexa-identity-public-edge     0/1  要 lunanexa/web:management-20260827-console-compat-10
                                                  → ErrImageNeverPull（policy: Never）
deployment/lunanexa-enterprise               0/1  CreateContainerError
deployment/lunanexa-workbench                0/1  CreateContainerError
```

**✅ 本次已修复。** 先证明了一件事：这些 edge 挂载的 nginx 配置是**纯反代**，没有自己的业务逻辑 ——

```
# configmap lunanexa-identity-edge-nginx / default.conf
location / { proxy_pass http://lunanexa-identity-gateway:8081; }
```

所以镜像只要"是个能跑的 nginx"即可，而不是必须匹配那个已不存在的构建。又验证了
`lunanexa-web` 其实就是 **nginx 1.27.5**（`Cmd: ["nginx","-g","daemon off;"]`，
`NGINX_VERSION=1.27.5`），而且正在服役的前门 `operator-4173-proxy` 用的就是它。
同时确认所有身份相关 pod 都被 `nodeSelector: lunanexa.io/role: management` 钉在管理节点，
所以别名打在管理节点就一定生效。

于是打两个别名（可加性、可回退）：

```sh
k3s ctr images tag docker.io/library/lunanexa-web:20260918 \
  docker.io/lunanexa/web:management-20260827-console-compat-10
k3s ctr images tag docker.io/library/lunanexa-web:20260918 \
  lunanexa-registry.lunanexa-registry.svc.cluster.local:5000/moon/lunanexa-web@sha256:a6136238fb0d39165fb26296b809786204fc6e74c2fee774e5103f7a4fe17550
```

**两个别名带来的连锁修复（都实测确认）：**

```
lunanexa-identity-internal-edge   2/2 Running
lunanexa-identity-public-edge     1/1 Running
lunanexa-identity-edge            2/2 Running     ← 同一个 digest 引用
lunanexa-enterprise               1/1 Running     ← 同一个 digest 引用
lunanexa-workbench                1/1 Running     ← 同一个 digest 引用
svc/lunanexa-console-public  ENDPOINTS: 10.42.0.27:8443,10.42.0.45:8443   ← 5003 的 302 就是它给的
```

并且 **5006 上的 OIDC discovery 通了**：

```
$ curl http://106.39.18.146:5006/realms/lunanexa/.well-known/openid-configuration
{"issuer":"http://106.39.18.146:5006/realms/lunanexa",
 "authorization_endpoint":"…/protocol/openid-connect/auth",
 "token_endpoint":"…/protocol/openid-connect/token",
 "introspection_endpoint":"…"…}
```

**而且操作员登录入口 5003 真的活了**（带 PKCE 的完整授权码跳转）：

```
$ curl -i http://106.39.18.146:5003/auth/oidc/start?audience=operator
HTTP/1.1 302 Found
Location: http://106.39.18.146:5006/realms/lunanexa/protocol/openid-connect/auth
  ?response_type=code&client_id=lunanexa-operator
  &redirect_uri=http%3A%2F%2F106.39.18.146%3A5003%2Fauth%2Foidc%2Fcallback
  &scope=openid%20profile%20email&state=…&nonce=…&code_challenge=…&code_challenge_method=S256
Set-Cookie: lunanexa_http_operator_oidc=…      ← 与 LUNANEXA_PUBLIC_HTTP_ENABLED=true 一致
```

跟到 Keycloak 之后是**真正的登录表单**（不是错误页），说明两个 client 都注册正确：

```
$ curl "<上面那个 auth URL>"
<form id="kc-form-login" …>        ← 含 username / password 字段
```

同时用 admin API 确认了 realm 与客户端：

```
realm lunanexa：client lunanexa-operator（confidential，redirect http://106.39.18.146:5003/auth/oidc/callback）
                client lunanexa-enterprise（confidential，redirect http://106.39.18.146:5005/auth/oidc/callback）
```

**5006 是"只服务 IdP"的边缘，这是设计如此**，不是缺陷 —— 它的配置只放行两条：

```
location = /            { return 302 /realms/lunanexa/account/; }
location ^~ /realms/lunanexa/ { proxy_pass https://lunanexa-platform-idp-service:8443; }
location ^~ /resources/       { proxy_pass https://lunanexa-platform-idp-service:8443; }
location /              { return 404; }     ← 所以 5006 上 /auth/oidc 返 404 是正常的
```

**剩下的那一个开关：公网明文 HTTP 上，控制台按设计拒绝管理员登录。**

用浏览器打开 `http://106.39.18.146:5003/`，控制台渲染出来但写着：

```
Administrative login is blocked on public plain HTTP. Use the protected localhost URL or install TLS first.
Organization sign-in requires HTTPS
```

原因在 `ui/browser_transport/transport.mbt:4-19`：`allows()` 只放行
`https:`、`localhost/127.0.0.1/[::1]`，或"端点 origin == 页面 origin == 部署声明的 public HTTP origin"。
而这个 origin 来自 `cmd/console/index.html:5` 的
`<meta name="lunanexa-public-http-origin" content="">` —— **签入时是空的**。
`docs/PUBLIC_HTTP_TRANSITION.md:180-190` 写得很清楚：

> Their shipped HTML contains an empty `lunanexa-public-http-origin` meta element, so public HTTP
> remains disabled by default. A deployment choosing temporary HTTP must set its content to the exact
> public origin, for example `http://106.39.18.146:5003` for the operator page.
> … This metadata is deployment policy, not cryptographic protection: HTTP remains vulnerable to
> network interception. Restoring HTTPS requires removing the opt-in as well as the coordinated
> gateway/identity changes above.

所以这是一个**部署策略选择**，不是 bug：要么装 TLS（正确做法），要么显式把那个 meta 填成
`http://106.39.18.146:5003` 并重新构建控制台 bundle（临时做法，明文可被中间人截获）。
**这一条我没有替你按** —— 它会把"公网明文下禁止管理员登录"这条安全默认关掉。

另外，即使开了这个开关，还要有可登录的身份：realm `lunanexa` 里原本**只有 1 个用户**
（`smoke-identity-20260904-1832@example.invalid`，且已绑定 TOTP），没有任何操作员/企业用户。
本次为了验证链路，我用 admin API 建了一个测试用户 `recon-operator@lunanexa.local`
（realm 开了 email-as-username，且默认要求 `CONFIGURE_TOTP`，两处都已处理），
口令保存在管理节点本地、**未入库**。这是环境准备，不是业务流程。

**第 3 跳的第二个子问题：OIDC 配置的端口和你在用的端口不是同一批。**

身份网关的配置（configmap `lunanexa-identity-ingress-config`，`LUNANEXA_IDENTITY_GATEWAY_MODE=proxy`）
把它自己钉在下面这套公开拓扑上：

| 配置项 | 值 | 修复前后 |
|---|---|---|
| `LUNANEXA_OIDC_ISSUER_URL` | `http://106.39.18.146:5006/realms/lunanexa` | 000 → **302/discovery 通** |
| `LUNANEXA_IDENTITY_CANONICAL_ISSUER` | `https://106.39.18.146:5006/realms/lunanexa` | 同上 |
| `LUNANEXA_OIDC_OPERATOR_REDIRECT_URI` | `http://106.39.18.146:**5003**/auth/oidc/callback` | 000 → **302 通** |
| `LUNANEXA_OIDC_ENTERPRISE_REDIRECT_URI` | `http://106.39.18.146:**5005**/auth/oidc/callback` | **仍 404**（5005 的 nginx 没有 `/auth` location） |
| `LUNANEXA_PUBLIC_HTTP_ENABLED` | `true` | — |

而运维实际在用的是 **4174（控制台）** 和 **5002（企业门户）**，这两个端口**没有 `/auth/*` 路由**：

```
4174/auth/oidc/start?audience=operator -> {"error":{"code":"NotFound",…}}   ← 落到控制面
5002/auth/oidc/start?audience=operator -> {"error":{"code":"NotFound",…}}   ← 落到控制面
5003/auth/oidc/start?audience=operator -> 302 到 Keycloak（本次修好）
5006/auth/oidc/start?audience=operator -> 404（该边缘只放行 /realms/ 与 /resources/，设计如此）
```

即：**OIDC 那一套是另一批端口（5003/5005/5006），运维手上那批（4174/5002）从来没接过
`/auth/oidc`。** 要收口：把 4174/5002 也接上 `/auth/oidc` 与 `/auth/session`（或反过来，
把运维的入口迁到 5003/5005），并让 5005 具备 `/auth` location，否则企业侧登录回来会 404。

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
（`ssl-client-verify: SUCCESS` + `ssl-client-subject-dn`）；这条路的边缘本次已经全部
`Running` 了，所以它现在是可用的，只剩端口与 client 登记要对齐（见 §2.5）。

### 2.5 前端 nginx 的两处关键配置（本次新增定位，含一个授权缺陷）

运维在用的前门由 configmap `operator-4173-proxy`（hostNetwork nginx）提供，
它同时监听 8081 / 4174 / 5000 / 5002 / 5005 / 5889。摘要：

```
server { listen 8081; listen 4174;
  location = /            { return 302 http://$host:$server_port/console/; }
  location /console/      { proxy_pass http://lunanexa-console:8080; }
  location /auth/         { proxy_pass http://lunanexa-CONTROL:8080;  … }   ← 关键
  location /v1/           { proxy_pass http://lunanexa-control:8080;  … }   ← 注入了 Bearer
  location /h3/  /h3r/  /glm53/ … }
server { listen 127.0.0.1:5000; … comfyui-public…:8188 }                    ← 5000 = ComfyUI
server { listen 127.0.0.1:5005; … proxy_pass http://192.168.2.175:5000 }    ← 5005 也指向 ComfyUI
server { listen 127.0.0.1:5002;
  location = /            { return 302 /enterprise/?demo=1; }
  location /enterprise/   { root /srv/portal; }
  location /auth/         { proxy_pass http://lunanexa-CONTROL:8080; … }    ← 同上
  location /v1/           { proxy_pass http://lunanexa-control:8080; … } }
```

**发现 1（这就是 404 的确切原因）：`location /auth/` 被代理到"控制面"，而不是身份网关。**
所以 4174/5002 上的 `/auth/oidc/start` 去问控制面，控制面没有 `/auth/*` 路由（它的鉴权路由
在 `/v1/auth/*`），于是回了那个 `{"error":{"code":"NotFound",…}}`。
一眼看去像"没有路由"，实际是**路由指错了对象**。

**发现 2（重要约束）：光把这行改指向网关还不够。** 网关在
`cmd/identity-gateway/server.mbt:610-611` 有一道硬闸：

```moonbit
guard host_and_audience(config, request) is Some((host, audience)) else {
  return send_error(connection, 400, "untrusted-browser-host")
}
```

`host_and_audience`（`server.mbt:74-86`）要求 `Host` 必须是**配置里登记过的**
重定向 URI 主机（operator 是 5003，enterprise 是 5005）。所以把 4174/5002 的 `/auth/`
直接改指网关，只会得到 `400 untrusted-browser-host`。
**结论：想用运维手上的端口，必须三处一起改** —— ① 前端 `/auth/` 指向网关；
② 网关的 `LUNANEXA_OIDC_*_REDIRECT_URI` 改到该端口；③ Keycloak 对应 client 的
redirect URI 同步登记。少一处都不通。本次实测也印证了这点：走 loopback 隧道访问 5003
（Host 变成 `127.0.0.1:5003`）时，拿到的是 **400**，正是这道闸。

**发现 3（另外两处错位）**：`5005` 现在 `proxy_pass http://192.168.2.175:5000`，也就是
**指向 ComfyUI**，而企业侧的重定向 URI 恰好配在 5005；企业门户实际在 5002。
另外 5000 也是 ComfyUI。即"门户入口 / OIDC 回调入口 / ComfyUI"三个东西的端口是错位的。

**发现 4（授权缺陷，建议单独跟进）**：两个 server 块的 `location /v1/` 都带了
`proxy_set_header Authorization "Bearer <64 位十六进制操作员令牌>"` —— 令牌**以明文写在这个
ConfigMap 里**，并被 nginx 注入到每一个 `/v1/` 请求上。后果是：
**任何能访问 4174 或 5002 的人，不需要任何会话就能以操作员身份调用控制面全部 `/v1/` API。**
这也解释了为什么控制台/门户在"没登录"的情况下仍能读到真实集群数据。
（本节只描述机制，不复述令牌值；建议改为由会话令牌驱动，并把该值收进 Secret。）

### 2.6 本次实际改动与验证：企业侧 OIDC 登录已能走到回调

**已改动三处（企业 audience 专用，操作员 5003 未受影响；改动前均已备份 configmap）：**

1. 前端 5002 的 `location /auth/` 由控制面改指身份网关，并补上
   `proxy_set_header Host $http_host`（不加这句网关只会看到上游名，必然 400）。
2. 网关 configmap：`LUNANEXA_OIDC_ENTERPRISE_REDIRECT_URI` 由 5005 改为
   `http://106.39.18.146:5002/auth/oidc/callback`（5005 本来就是 ComfyUI 的入口）。
3. Keycloak `lunanexa-enterprise` 客户端：**追加**（不删除）5002 的回调 URI。

**验证 —— 两个 audience 都给出正确的 PKCE 跳转：**

```
5002/auth/oidc/start?audience=enterprise -> 302
  Location: …/protocol/openid-connect/auth?…&client_id=lunanexa-enterprise
            &redirect_uri=http%3A%2F%2F106.39.18.146%3A5002%2Fauth%2Foidc%2Fcallback
            &…&code_challenge=…&code_challenge_method=S256
  Set-Cookie: lunanexa_http_enterprise_oidc=…
5003/auth/oidc/start?audience=operator -> 302（回归通过，client_id=lunanexa-operator）
```

**验证 —— 真的在浏览器里完成了 OIDC 登录。** 用 CDP 抓的网络时序：

```
gate text: NX / LunaNexa enterprise access / Sign in or create a n…
click sso: ok
url now: http://106.39.18.146:5006/realms/lunanexa/protocol/openid-connect/auth?…client_id=lunanexa-enterprise…
fill: submitted
final url: http://106.39.18.146:5002/enterprise/?demo=1
--- /auth/ responses ---
   401 :5002/auth/session
--- set-cookie seen ---
   lunanexa_http_enterprise_oidc [HttpOnly,Path=/] status=302   ← start 发的 flow cookie
   AUTH_SESSION_ID … / KC_RESTART …                             ← Keycloak 侧
   lunanexa_http_enterprise_oidc [HttpOnly,Path=/] status=303   ← callback 换发的会话 cookie ✔
```

即：**Keycloak 认证成功、回调执行成功并换发了会话 cookie**。这比之前"点登录就 404"是实质跨越。

**但会话没落到门户，原因有两个，一个是缺陷、一个是还没打通的最后一跳。**

**缺陷：登录成功后立刻被塞进演示门户。** `final url` 是 `…/enterprise/?demo=1` ——
因为前端 5002 的 `location = /` 是**无条件** `return 302 /enterprise/?demo=1;`。
于是刚登录的用户（带着真实会话 cookie）也被导到 demo 页面，而 demo 模式**完全不联系控制面**
（§4 已实测零请求），用户看到的是 `org-northstar / 1 / 1 / 2 / CNY 18,420` 那套假数据。
**"登录后看不到自己的真实数据"这件事，根因就在这里**，而且代价极低：
`location = /` 应当在存在有效会话时才跳真实门户。这一条本次只做定位，未改。

**最后一跳：网关把会话 cookie 换成 `lnxs_` 租户会话时失败。** 页面上下文直接探测：

```
GET /auth/session  ->  401 {"error":"browser-session-required"}      （未登录时，正常）
GET /auth/session  ->  503 application/json                          （登录后那次）
GET /auth/session  ->  401 {"error":"browser-session-required"}      （随后又变回 401）
```

`503` 出现在回调刚完成之后，之后又退化为 `401` —— 像是"cookie 有效 → 与控制面交换失败 →
网关清掉 cookie"。网关侧日志**没有任何错误输出**，而网关镜像里没有 shell，无法进去抓包，
于是从拓扑上定位，**根因已确认**：

```
# svc/lunanexa-identity-relay 的 selector
app=lunanexa-control,lunanexa.io/browser-identity-sidecar=enabled

# 控制面 Pod 的三个容器
runtime-loopback-proxy      args: 127.0.0.1 19090  lunaflux-runtime…:43120
control                     args: (LUNANEXA_LISTEN_ADDRESS=0.0.0.0:8080,
                                    LUNANEXA_IDENTITY_LISTEN_ADDRESS=127.0.0.1:8082)
runtime-loopback-proxy-glm  args: 127.0.0.1 19091  glm53-exl3…:8899

# 从另一个 Pod 实测（curl 在 operator-4173-proxy 里）
relay8081 = 000     ← 连不上，没人监听
gateway8081 = 400   ← 网关本身是活的
podip:8081 = 000 / podip:8082 = 000
```

也就是说：**控制面 Pod 带着 `lunanexa.io/browser-identity-sidecar=enabled` 这个标签，
`lunanexa-identity-relay` 服务因此把它选为端点，但 Pod 里根本没有身份 relay 这个容器** ——
那两个 `runtime-loopback-proxy*` 是给 runtime 和 GLM 做回环代理的，args 里写得很清楚，
与身份无关。于是 8081 上没有任何监听，网关所有走 relay 的调用都失败，
`/auth/session` 自然换不出 `lnxs_` 会话。

**这就把整条链的最后一跳钉死了：缺的是"browser-identity 旁车容器"，
而不是密钥、不是端口、也不是 TLS。** 顺带解释了为什么
`kubectl get endpoints lunanexa-identity-relay` 显示 `<none>` 而 EndpointSlice 里却有一个
`ready:true` 的地址 —— 标签匹配上了，端口却是空的。

（另外核对了断言密钥：网关与控制面**都引用同一个 secret 的同一个 key**
`lunanexa-identity-ingress-credentials/identity-assertion-secret`，所以密钥不是原因。）

**✅ 已修复并验证。** 缺失的旁车在仓库里本来就有定义 ——
`deploy/oidc-browser-ingress-controller-patch.yaml` 给出了完整的 `identity-relay` 容器
（模式 `relay`、监听 `0.0.0.0:8081`、转发到 `http://127.0.0.1:8082`、
只放行 POST 的 `/v1/auth/session:exchange` 与 `/v1/auth/register`）。**它只是从未被应用。**

按既有定义执行，分两步（改动前已备份 deployment）：

1. **先做冒烟**：把该镜像按 `mode=relay` 起一个临时 Pod（不碰控制面），结果
   `1/1 Running`，另一个 Pod 访问 `http://10.42.0.48:8081/health` 得到 **200** ——
   证明镜像与参数都对。
2. **再把旁车打进控制面 Deployment**（strategic merge，容器按名字合并）：

```
control pod: containers = ['identity-relay','runtime-loopback-proxy','control','runtime-loopback-proxy-glm']
            4/4 Running，identity-relay ready=True restarts=0
relay8081 = 200        ← 修复前是 000
```

**然后关键结果：`/auth/session` 从 401/503 变成 200，并且真的换出了租户会话：**

```
GET /auth/session -> 200
{"session_token":"lnxs_<…>","csrf_token":"<…>","expires_unix_ms":1790037781541}
```

也就是说 **"cookie → `lnxs_` 租户会话"这一跳通了**，而且这条会话是**在浏览器里
经真实 OIDC 登录拿到的**（`session_token` 带 `lnxs_` 前缀，`csrf_token` 非空，
与 `cmd/enterprise/main.mbt:2333-2334` 的校验条件一致）。这是整条链到目前为止最深的一次打通。

**但门户界面仍停在登录门。** 实测该页面加载时确实发起了 `/auth/session`，
**之后再没有任何 `/v1/` 请求**（`performance` 里只有 `/auth/session` 一条），
于是渲染回登录门。对照源码，入口处 `Bootstrap` 会走
`bootstrap_command → BootstrapReady → organization_bootstrap_command`
（`cmd/enterprise/main.mbt:2324-2360、3439-3459`），
`BootstrapReady` 之后应当带着 token 去调 `/v1/`；现在它没有走到那一步。
这属于**前端启动流程**的问题，与已经修好的身份链路分开，是下一步要单独查的。

### 2.7 最后一跳的真正原因：一个 JSON 契约不匹配（两侧同病，已确证）

身份链路修好后，`/auth/session` 已经返回 200 与真实 `lnxs_` 会话，但门户**仍停在登录门**。
实测该页加载时确实请求了 `/auth/session`（拿到 200），**之后再无任何 `/v1/` 请求**，
且控制台里没有任何报错。用页面上下文复刻应用自己那次 fetch（同参数、同 credentials）也返回
`ok=true status=200`，所以问题不在网络。

**根因（可复现，已确证）：JS 后端上 `Int64::from_json` 要求数字以"字符串形式"出现，
而网关发的是 JSON 数字。** 用一个仓库外的临时 MoonBit 包（`/tmp/jt`，`--target js`）复现：

```moonbit
priv struct Bootstrap {
  session_token : String
  csrf_token : String
  expires_unix_ms : Int64
} derive(FromJson)

// 网关今天发的形式：数字
test "number form" {
  let body = "{\"session_token\":\"lnxs_x\",\"csrf_token\":\"c\",\"expires_unix_ms\":1790037781541}"
  ...
}
```

```
number form -> FAILED: JsonDecodeError((/expires_unix_ms,
              Int64::from_json: expected number in string representation))
string form -> decoded expires=1790037781541
```

即：**数字形式必然失败，字符串形式才能解出。**

**两个产品都踩了同一个坑**，两处声明完全同构、都是 `derive(FromJson)`：

```moonbit
// cmd/enterprise/main.mbt:9-13
priv struct GatewayBrowserBootstrap {
  session_token : String
  csrf_token : String
  expires_unix_ms : Int64     // ← 解不了 JSON 数字
} derive(FromJson)

// cmd/console/main.mbt:202-206
priv struct GatewayBrowserSession {
  session_token : String
  csrf_token : String
  expires_unix_ms : Int64     // ← 同一处坑
} derive(FromJson)
```

于是两侧的启动流程都会走成"拿不到会话"：

- 企业侧 `cmd/enterprise/main.mbt:2324-2360`：`@json.from_json` 抛错 → 被
  `catch { _ => BootstrapUnavailable(generation) }` 吞掉 → 回登录门。
- 控制台 `cmd/console/main.mbt:3213-3221`：同一句解析 → `GatewaySessionUnavailable`
  → 回登录门。

**这就是"登录成功却进不去"的真正原因**，而且它同时解释了为什么之前两侧都像"没有会话"。

**这也是一个可诊断性缺陷**：异常被 `catch { _ => … }` 丢弃，界面上只表现为"回到登录门"，
既没有错误码也没有日志，导致这条链路此前一直被误判为网络/端口/密钥问题。

**修法已确定并实施：改生产侧那一行，而不是改三个消费侧。**

先查了"仓库的既定惯例到底是哪种"。用同一个临时包实测：

```
ToJson emits: {"session_token":"lnxs_x","expires_unix_ms":"1790037781541"}
int64 to_json: "1790037781541"
round-trip ok: 1790037781541
```

即 **MoonBit 的 `ToJson for Int64` 在 JS 后端就是把 int64 输出成"带引号的字符串"**，
`FromJson` 也正好要求这种形式。所以仓库的惯例是 **int64 走字符串**，
而网关那段**手写**的 JSON 是**唯一的例外**。全仓库扫描确认只有这一处：

```
$ grep -rn 'unix_ms\":\{' --include=*.mbt cmd/ api/
cmd/identity-gateway/server.mbt:368   ← 仅此一处
```

**而且这个 body 有三个消费侧，都是同一句解析**：

| 消费侧 | 结构体 | 结果 |
|---|---|---|
| 企业门户 | `cmd/enterprise/main.mbt:18` `GatewayBrowserBootstrap` | → `BootstrapUnavailable` → 登录门 |
| 运维控制台 | `cmd/console/main.mbt:203` `GatewayBrowserSession` | → `GatewaySessionUnavailable` → 登录门 |
| workbench / 试用 | `cmd/workbench/trial_session.mbt:2` `TrialBrowserSession` | → `fail("invalid or expired browser session")` |

所以改生产侧一行，三个消费侧同时修好；改消费侧则要动三处、并和仓库惯例逆向。

**已实施**：把 `cmd/identity-gateway/server.mbt` 里那一段抽成
`fn browser_session_body(session)`，并把 `expires_unix_ms` 的值加上引号：

```moonbit
fn browser_session_body(session : GatewayCookie) -> String {
  "{\"session_token\":\"\{session.bearer}\",\"csrf_token\":\"\{session.csrf}\",\"expires_unix_ms\":\"\{session.expires_unix_ms}\"}"
}
```

并加了回归测试（`cmd/identity-gateway/main_wbtest.mbt`）：

```moonbit
test "browser session body encodes expires_unix_ms as a string" {
  ...
  assert_true(body.contains("\"expires_unix_ms\":\"1790037781541\""))
  assert_false(body.contains("\"expires_unix_ms\":1790037781541"))
}
```

`moon test cmd/identity-gateway --target native` → **17/17 通过**。

**注意：这只改到了源码。线上网关仍然发数字形式**，要等重建并重滚 `lunanexa-identity-gateway`
才会生效（这是下一步）。

另外建议（未做）：把三处 `catch { _ => … }` 里丢弃的原因至少记一条日志，或带进 UI ——
这条 bug 之所以能藏这么久，正是因为它被静默吞掉了。

### 2.8 修复已上线并验证：门户首次进入"登录后的 shell"

按 SOP §5.1 的六步把带修复的网关镜像做完并重滚（细节见 §5 第 1 条）：

```
构建    : moon build cmd/identity-gateway --target native --release  → (9 warnings, 0 errors)
镜像    : deploy/cluster/build-identity-gateway-image.py  → GATEWAY-IMAGE-OK
里层校验: 新镜像最后一层的 /usr/local/bin/lunanexa-identity-gateway
          sha256 = 1a82244e… 与刚构建的完全一致（下面是旧的 2064624 字节版本）
推 registry: …/acceptance/identity-gateway:20260922-sessionfix
          manifest sha256:4135e0dff89f3410af43624bcdcb3cd3a31e6a710d3249f295f49a2ff4d772a6
铁律验证: 删掉本地那份 → 从 registry 拉回来 → 成功复现 ✔
          registry tags/list 里出现 "20260922-sessionfix" ✔
重滚    : set image …@sha256:4135e0df…  →  2/2 Running，两个 Pod 都用新 digest
```

**修复生效的直接证据**（浏览器上下文里探测 `/auth/session`）：

```
status=200 {"session_token":"lnxs_…","csrf_token":"…","expires_unix_ms":"1790038426940"}
                                          ↑ 现在是带引号的字符串（修复前是裸数字）
```

**而且门户第一次进到了"登录后的 shell"**。对比之前（停在登录门，只有
`Sign in or create an account`），现在打开 `http://106.39.18.146:5002/enterprise/`（不带 `?demo=1`）：

```
Organization setup · secure browser session; ends on logout or expiry
Log out
…完整导航（Overview / Get started / … / WebIDE）…
Not connected · Tenant scoped
Operation: The action failed. Refresh and retry; …
```

即 **JSON 契约这一环彻底通了**：会话被正确解码、门户进入已认证外壳。
"登录成功却只能看到登录门"这个从第 9 轮追到现在的症状结束了。

**下一个卡点已经抓到了确切那一条请求：**

```
REQ  GET :5002/v1/portal/self/organizations
RES  401 :5002/v1/portal/self/organizations
```

门户拿会话之后向控制面要自己的组织，得到 **401**，于是显示
`Not connected` + 那句不透明的 `The action failed.`。

**原因基本可以锁定在前门那条令牌注入上**（§2.5 发现 4）：前门 nginx 对**每一个** `/v1/`
请求都 `proxy_set_header Authorization "Bearer <操作员令牌>"`，把浏览器自己发的
`lnxs_` 会话头**覆盖掉**。控制面于是看到的是操作员令牌而不是门户会话，
`/v1/portal/self/organizations` 这种要"门户主体"的路由自然拒绝。

也就是说：**那条"明文内嵌操作员令牌"不只是安全气味，它正在实质性地破坏门户的会话鉴权。**
这同时解释了为什么控制台在"没登录"时反而有数据 —— 它吃的就是被注入的操作员令牌。

修法需要做一个明确的取舍（属于运维/安全决策，与本报告 §5 第 12 条同一件事）：
前门要么不再无条件覆盖 `Authorization`（有会话就放会话，没有才用静态令牌），
要么把"浏览器会话"和"静态令牌回退"分成两条路由。**这一步我没有替你按。**

### 2.9 企业侧拿到真实租户会话并渲染成功；但两侧仍未对帐

**先修掉了那个 401。** 前门对**每一个** `/v1/` 请求都无条件覆盖 `Authorization`，
把浏览器的 `lnxs_` 会话冲掉。改成标准 `map`：**调用方自己带了就用它，没带才回落到静态令牌。**

```nginx
  map $http_authorization $lunanexa_authorization {
    default $http_authorization;
    ''      "Bearer <operator-token>";
  }
  location /v1/ { proxy_pass http://lunanexa-control:8080;
                  proxy_set_header Authorization $lunanexa_authorization; gzip on; }
```

（改动前备份了 configmap；`nginx -t` 通过后 reload；4174 控制台仍 200。）

**效果 —— 会话鉴权的那些接口全部转正：**

```
GET :5002/v1/portal/self/organizations  ->  200   （修复前 401）
GET :5002/v1/portal/self                ->  200
GET :5002/v1/auth/self                  ->  200
GET :5002/v1/auth/trial                 ->  200
GET :5002/v1/auth/sessions              ->  200
```

**而且企业侧第一次渲染出真实租户。** 打开 `http://106.39.18.146:5002/enterprise/`：

```
subject-b131b8c579a5901fe5ea97fe · trial-org-b131b8c579a5901fe5ea97fe · secure browser session
trial-org-b131b8c579a5901fe5ea97fe            Tenant scoped
Enterprise access loaded.
FREE SHARED-INFERENCE TRIAL / Your trial is ready
23h remaining · 2026-09-22 16:43:10 UTC · Requests 0/100 · text.qwen
Create trial API key
```

也就是说：**真实 OIDC 首次登录真的建立了受限试用账户，门户把它读出来并渲染了。**
`Not connected` 与那句 `The action failed.` 都消失了。目标是"企业侧注册企业"这一步，
到这里才第一次有了真实数据（此前全是 demo 夹具或 `Not connected`）。

**但两侧还是没有对帐 —— 这是一个新的、明确的缺口。** 同一时刻管理侧读到的仍是：

```
Users & access
0 users · 0 grants
Trial adoption
Trial statistics unavailable. Refresh after checking controller support.
```

即：**企业侧已经存在一个试用组织/账户，管理侧却报 0 用户，并且自己声明"试用统计不可用"。**
这正是本次任务要找的那类"两侧状态不一致"。两种可能都需要进一步确认：
要么控制台的 Users & access 列的不是同一个域（它页面自称管的是
"control-plane identities and time-bounded access grants"），
要么这条链在"企业侧建号 → 管理侧可见"之间确实断了。

**另外说明**：这次改动让那个静态操作员令牌从"无条件覆盖"降级为"仅在调用方没有凭据时的回落"。
它不再破坏会话鉴权了，但"这个令牌该不该存在于前端 ConfigMap 里"这个问题**依然没解决**，
仍列在 §5 第 12 条。

### 2.10 追那条"0 users"：账目层面其实是通的，坏的是显示

上一节说"管理侧报 0 用户"，我去把它查实了。结论比预期细，而且**不能一口咬定是数据断链**。

**账目层面：通。** 用前门（nginx 会为无凭据的调用注入操作员令牌）直接问控制面：

```
GET /v1/accounts -> 200
[{"account_id":"account-3b407b45…","display_name":"WebIDE Operator","roles":["EnterpriseUser"],"state":"Active",…},
 {"account_id":"account-b131b8c579a5901fe5ea97fe","subject_ref":"subject-b131b8c579a5901fe5ea97fe",
  "identity_issuer":"https://106.39.18.146:5006/realms/lunanexa",
  "display_name":"Recon Operator","roles":["EnterpriseUser"],"state":"Active",…}]

GET /v1/accounts/trial-summary -> 200
{"registered_trials":1,"active_trials":1,"expired_trials":0,"converted_trials":0,"generated_unix_ms":"1790009882396"}
```

第二条 `subject_ref` 正是企业侧会话条上那个 `subject-b131b8c5…`。
**也就是说：企业侧那次真实 OIDC 首次登录确实在控制面建了账户，`/v1/accounts` 读得到，
试用统计也把它算成 `registered_trials:1, active_trials:1`。这一层是对得上的。**

**那控制台为什么显示 0？** 读代码后要分成两件事，不能混为一谈：

1. **`0 users · 0 grants` 很可能不是缺陷。** `cmd/console/main.mbt:1708-1745`
   的 `load_console_access_reads` 里，`users` 取自 **workspace 目录**
   （`workspace.users`），`grants` 取自 `access_packages` / `exclusive_node_leases`。
   这些是与"账户"**不同的授权域**：企业侧拿到的是账户 + 受限试用，
   并没有 workspace 用户或访问授权。所以这两个 0 可能是正确的，
   只是页面把"账户"和"工作区用户/授权"并排放在同一屏、都叫 users，读起来像是在自相矛盾。
   **这一点需要再确认一次才算数**（要核对 workspace 目录里确实没有该主体）。
2. **`Trial statistics unavailable` 是真缺陷。** 同一段代码里，
   `trial_summary` 那句是**唯一带 catch 的**：

   ```moonbit
   let trial_summary : @ui.TrialSummary? = Some(@json.from_json(parse_console_json(
       request("GET", endpoint, "/v1/accounts/trial-summary", token)))) catch {
     // Supplemental statistics are unavailable, never zero, on older controllers.
     _ => None
   }
   ```

   而这个接口**返回 200 且内容正常**（见上）。按它自己的语义，出现
   "unavailable" 只可能是**解码抛了异常被吞掉**。也就是：
   **接口有数据、页面说没有** —— 又是"静默吞异常"这一类，
   与 §2.7 那个 JSON 契约问题同源（都是解码失败被 `catch` 掩盖成空态）。

   注意这个 payload 的形状很可疑：计数是**裸数字**（`1`、`0`），
   而 `generated_unix_ms` 是**字符串**。两侧类型若有一边写成 `Int64`，
   在 JS 后端就会因为"数字/字符串"不匹配而抛错（§2.7 已证明这条机制）。
   下一步就是比对 `@ui.TrialSummary` 的字段类型与这个 payload。

**所以这一条要修正上一节的措辞**：不是"两侧数据没对上"，而是
**账户层面对上了，管理侧的显示层没反映出来**；其中"试用统计不可用"是明确的解码缺陷，
"0 users · 0 grants" 则可能只是把不同的授权域并在同一屏展示。

### 2.11 更正：不是"不同的授权域"，是整块访问读取解码失败被吞掉

§2.10 我猜"`0 users · 0 grants` 可能只是把不同授权域并排展示"。**这个猜测是错的**，
继续查下去把它排除了，结论更简单也更严重。

**先把每一条输入都单独验一遍**（都是从控制台页面里发、经由前门）：

```
/v1/workspace                    -> 200  len=19181
/v1/onboarding/access-packages   -> 200  len=2575
/v1/exclusive-node-leases        -> 200  len=2      ([])
/v1/accounts                     -> 200  len=803
/v1/accounts/trial-summary       -> 200  len=117
```

**五条全是 200，而且内容都不空**（workspace 有 19 KB）。所以数据都在，不存在"域不同所以是 0"
——如果真是"没有 workspace 用户"，那个 payload 不会这么大。

**再看那段代码的结构，就说得通了**（`cmd/console/main.mbt:1708-1745`）：

```moonbit
let workspace  = @json.from_json(…)   // /v1/workspace        ← 无 catch
let accounts   = @json.from_json(…)   // /v1/accounts         ← 无 catch
let trial_summary = Some(@json.from_json(…)) catch { _ => None }   // 唯一带 catch
let access_packages = @json.from_json(…)   // ← 无 catch
let exclusive_leases = @json.from_json(…)  // ← 无 catch
```

**这个函数里只有 trial_summary 一句带 catch。** 所以只要**前面任意一条**（workspace / accounts /
access-packages / exclusive-leases）解码抛异常，整个函数就抛出，调用方回落到默认空状态，
于是**三个症状同时出现**：`0 users · 0 grants`、`Trial statistics unavailable`、
以及那句 `This console is using the localhost development-token fallback`。

**也就是说：这两个"0"和"不可用"是同一个被吞掉的解码异常的三种表现，
而不是三个独立问题。** 数据是齐的，坏在控制台的解码层。

顺带把 §2.10 的另一半也钉住了：`@ui.TrialSummary` 只有 4 个 `Int` 字段，
我用离线复现（`/tmp/jt`，`--target js`）把它喂给那个真实 payload：

```
decoded registered=1 active=1
```

**它解码是好的。** 所以"试用统计不可用"不是这个结构体的问题，
而是**同函数里更靠前的那次解码先抛了** —— 与上面的推断一致。

**下一步（未做）**：把这四个 payload 分别喂给它们声明的类型
（`@workspace.WorkspaceDirectorySnapshot`、`Array[@ui.AccountView]`、
`Array[@ui.AccessPackageView]`、`Array[@nodelease.ExclusiveNodeLease]`），
用同样的离线手法定位是哪一条、以及是哪个字段不匹配。
另外建议：这段代码应像 §2.7 那样**至少把异常记下来**，
否则一个解码 bug 会同时伪装成"没人"、"没授权"、"统计不可用"三件事。

### 2.12 收窄：workspace 里其实有 12 个用户、16 条授权，所以那两个 0 一定是显示层

继续收窄 §2.11 那条。把 `/v1/workspace` 拉下来看结构：

```
top keys: ['schema_version', 'users', 'access_grants', 'leases']
users         : 12 items   keys=[version, user_id, subject_ref, display_name, email, state, created_unix_ms, identity_receipt]
access_grants : 16 items   keys=[version, grant_id, user_id, tenant_ref, access, starts_unix_ms, expires_unix_ms, state, policy_receipt]
leases        : 16 items   keys=[version, lease_id, tenant_ref, subject_ref, access, limits, starts_unix_ms, expires_unix_ms, state, policy_receipt]
```

**workspace 里有 12 个用户、16 条授权。** 所以控制台的 `0 users · 0 grants`
**不可能是"数据本来就是空的"** —— 一定是显示层（解码失败后回落默认空态）造成的。
这一条现在可以确定地写下来了。

**同时把几个常见嫌疑逐一排除：**

| 嫌疑 | 结论 | 依据 |
|---|---|---|
| `null` 字段（Option 解码陷阱） | **排除** | 两个大 payload 里 `null` 计数都是 0；且 `parse_console_json` 本身就在解码前把 `Null` 摘掉（`cmd/console/main.mbt:1196-1208`） |
| int64 收到裸数字 | **排除** | payload 里所有 `*_unix_ms` 都是**字符串**（`"1788015701000"`），与 §2.7 证明的惯例一致 |
| 配额字段（`max_*`）收到裸数字 | **排除** | 声明是 `Int`（`workspace/types.mbt:152-156,177`），裸数字可解 |
| 枚举变体不认识 | **排除** | payload 里出现的 `UserActive` / `GrantExpired` / `Developer` / `TextGenerate` 等，在 `workspace/types.mbt` 里全部存在 |

**所以失败点还没抓到，但范围已经很小了。** 下一步：把 `users[0]` / `access_grants[0]` / `leases[0]`
这三个元素（各约 300–570 字节，见下）分别喂给它们声明的类型
（`@workspace.WorkspaceUser` / `WorkspaceAccessGrant` / `WorkspaceLease`），
用 §2.7 那套离线复现手法定位是哪一个、哪个字段。

```json
// users[0]
{"version":"lunanexa.workspace.v1","user_id":"smoke-moongate","subject_ref":"static-inference-subject",
 "display_name":"MoonGate Smoke User","email":"smoke-moongate@example.invalid","state":"UserActive",
 "created_unix_ms":"1788015701000","identity_receipt":"smoke-authorized-by-owner-202…"}

// leases[0] 的 limits 里同时有字符串和裸数字：
{"limits":{"max_active_sessions":1,"max_session_duration_ms":"300000","capabilities":[…]}}
```

（最后一个值得特别看一眼：`max_session_duration_ms` 是**字符串**而 `max_active_sessions` 是**裸数字**，
同一个对象里两种形态并存 —— 如果 struct 把前者声明成 `Int` 或把后者声明成 `Int64`，就会在这里炸。）

### 2.13 找到了：控制面把一个 Option 序列化成了数组，控制台按标量解，于是整块回落

§2.12 说"失败点还没抓到，但范围很小"。抓到了，而且是一条完整的因果链。

**先说顺手修掉的一个既有缺陷**：`cmd/console` 的测试**在 HEAD 上根本编译不过** ——
`cmd/console/main_wbtest.mbt:1296` 的测试辅助 `node_row_heartbeat` 把
`declared_memory_mib` 写成了**位置参数**，而它的 7 个调用点全都按**标签参数**传
（`declared_memory_mib=65536`），报
`This function has no parameter with label declared_memory_mib~`。
改成 `declared_memory_mib~ : Int` 后 **`moon test cmd/console --target js` → 61/61 通过**。
（这类"改了签名没改调用点"的漂移，正好发生在之前那轮内存指标改动里。）

**然后在能编译的包里做了离线解码**（用 §2.7 的手法，把线上真实 payload 喂给声明类型）：

```
workspace user        -> OK
workspace access grant-> OK
workspace lease       -> OK
access package        -> FAILED: JsonDecodeError((/grant_id, String::from_json: expected string))
```

**就是它。** 再看线上 `/v1/onboarding/access-packages` 的真实元素：

```
package_id            = "access-account-3b407b45…"
account_id            = "account-3b407b45…"
display_name          = "WebIDE Operator"
grant_id              = ["grant-3b407b45…"]        ← 是数组
lease_id              = ["lease-3b407b45…"]        ← 是数组
lease_state           = ["Active"]                 ← 是数组
expires_unix_ms       = ["1792552691962"]          ← 是数组
approved_model_aliases= ["tiny-bf16", "incoai-glm-5.3-flash-dflash2", …]
account_ready         = true                        ← 其余是标量
state                 = "Ready"
```

而控制台的 `@ui.AccessPackageView`（`ui/pkg.generated.mbti:159-176`）把这些声明成**标量**：
`grant_id : String?`、`lease_id : String?`、`lease_state : WorkspaceLeaseState?`、`expires_unix_ms : Int64?`。

**生产侧为什么发数组？** 在 `api/access_onboarding_http.mbt:329-345`，这几个字段是直接塞进
JSON 映射字面量的**裸 `Option` 值**：

```moonbit
"grant_id": grant.map(value => value.grant_id),          // Option[String]
"lease_id": lease.map(value => value.lease_id),          // Option[String]
"lease_state": lease_state,                              // Option[LeaseState]
"expires_unix_ms": lease.map(value => value.expires_unix_ms),   // Option[Int64]
"approved_model_aliases": aliases.to_json(),             // 只有这一行显式转了 Json
```

**而 MoonBit 的 `ToJson for Option` 就是把 `Some(x)` 输出成单元素数组、`None` 输出成 `null`** —— 离线实测：

```
Some       -> ["grant-1"]
None       -> null
Some Int64 -> ["1792552691962"]
```

于是形状对不上，`/grant_id` 处抛错；因为 `load_console_access_reads` 里只有 trial_summary 带 catch，
**整个函数抛出 → 调用方回落默认空态 → 三个症状同时出现**：
`0 users · 0 grants`、`Trial statistics unavailable`、dev-fallback 提示。

**所以这条链完全闭合了**：数据一直都在（12 用户 / 16 授权 / 2 个访问包），
坏在**生产侧多包了一层数组** + **消费侧静默吞掉解码错误**，两者叠加才伪装成"管理侧什么都没有"。

**修法（明确，未做）**：把那 4 个字段改成"有值就发标量、没值就发 null"，
例如 `match grant { Some(v) => v.grant_id.to_json(), None => Json::Null }` ——
消费侧的 `parse_console_json` 本来就会在解码前摘掉 `Null`，
所以 `String?`/`Int64?` 正好接得住。改完要重建并重滚控制面镜像（走 SOP §5）。
另外建议这段生产代码也按 §2.7 的教训，别再把 Option 直接丢进 JSON 字面量。

### 2.14 为什么生产侧会写成裸 Option：`Json` 的构造器在这个版本是只读的

准备动手修 §2.13 那个生产侧 bug 时，先撞上一个语法事实，值得记下来 ——
**它解释了作者当初为什么只能写裸 `Option`。**

想写"有值发标量、没值发 null"，自然写法是构造一个 `Json` 空值，结果三个写法全部编译失败：

```
let a : Json = Json::Null              → Error 4036: Cannot create values of the read-only type: Null.
let m : Map[String, Json] = Map([("k", Json::Null), …])
                                       → Error 4036: Cannot create values of the read-only type: Null.
Json::Object(m)                        → Error 4036: Cannot create values of the read-only type: Object.
```

`Json` 这个枚举定义在 **`moonbitlang/core/builtin`**（`builtin/json.mbt:26`，也就是在前导库里，
所以仓库里到处直接写 `Json`），而它的**构造器在当前版本是只读的**：
**不能显式 `Json::Null` / `Json::Object` 去造值**，只能通过 `.to_json()` 或 `@json.parse` 得到。

**这就串起来了**：

- 作者不能写 `Json::Null`，于是把裸 `Option` 直接放进 JSON 字面量，指望它自然变成"有值/null"；
- 但 `ToJson for Option` 给的是 **`Some(x) → [x]`**（§2.13 已实测），不是标量；
- 而消费侧又**只对 trial_summary 一个字段做了 catch**，解码一抛整块就回落成空态；
- 三层叠加，才让"12 个用户 / 16 条授权"显示成 `0 users · 0 grants`。

**所以修法要绕开"构造 Json 空值"这条路。** 可行且干净的做法是：
**用 `Map[String, Json]` 动态装配、最后 `.to_json()` 成对象** ——
缺的字段干脆**不放进去**（消费侧的 `String?` / `Int64?` 本来就能接受"字段不存在"），
`Some` 的字段放 `v.to_json()` 标量。这样既不需要造 null，也不需要改契约。

```moonbit
let mut package : Map[String, Json] = Map([])
package["package_id"] = "access-\{account.account_id}".to_json()
… 其余标量字段照旧 …
match grant { Some(v) => package["grant_id"] = v.grant_id.to_json(), None => () }
match lease {
  Some(v) => {
    package["lease_id"] = v.lease_id.to_json()
    package["expires_unix_ms"] = v.expires_unix_ms.to_json()
  }
  None => ()
}
… 最后 package.to_json() …
```

**这一条我还没动手**：它是约 40 行字面量的结构改动，改完还要按 SOP §5 重建并重滚控制面镜像，
属于下一轮的一整块工作。先把"为什么会长成这样"和"应该怎么改"记全。

### 2.15 修复上线并验收：管理侧终于显示出真实数据，两侧在账目层对上了

§2.13/§2.14 定位、§上一轮改好源码之后，按 SOP §5 走完控制面的重建与重滚，**在真实页面上验收通过**。

**先看接口形状（决定性）**：

```
GET /v1/onboarding/access-packages -> 200，2 个包
   grant_id        = "grant-3b407b45…"    (type=str)   ← 修复前是 ["grant-…"]
   lease_id        = "lease-3b407b45…"    (type=str)
   lease_state     = "Active"             (type=str)
   expires_unix_ms = "1792552691962"      (type=str)
```

**再看控制台页面**（同一个 `Users & access`，前后对比）：

| | 修复前 | 修复后 |
|---|---|---|
| 概要 | `0 users · 0 grants` | **`12 users · 16 grants`** |
| 试用统计 | `Trial statistics unavailable.` | **`Registered trials 1 / Active trials 1 / Expired 0 / Converted 0`** |

**这就是"两侧对帐"第一次真正对上**：企业侧那次真实 OIDC 首次登录建出来的试用账户，
在管理侧显示为 `Registered trials: 1 / Active trials: 1`，
而 workspace 目录里的 12 个用户、16 条授权也如实渲染出来了。
在此之前，管理侧无论怎么看都是 `0 users · 0 grants` + "统计不可用"。

**这一轮实际做了什么**（全部可复核）：

1. 把同一处修复打到节点源码树（精准补丁，改前备份），
2. `moon build cmd/control` + `cmd/loopback-proxy`（linux/amd64，0 errors），
3. 用 `deploy/cluster/build-control-image.py` 原地覆盖 `lunanexa-control:20260918`
   —— 它**成功找到并替换了二进制层**（`replacing binary layer 1 (42 files)`），
   这正是被我补上的 `isfile()` 修复在起作用；
4. 按 SOP ⑤ 确认 digest 变了（`eb82fdc6…` → `8e9c4dda…`）才重滚；
5. `rollout restart` → `4/4 Running`，然后按上面的两种方式验收。

**顺带说明**：控制面这个 tag 是本地覆盖式的（不像网关要推 registry），
所以 SOP §2 的"删掉本地再从 registry 拉回"那一步在这里不适用，
取而代之的是 SOP §5 自己的判据 —— **digest 必须变**，我照做了。

**至此，本次任务真正的堵点清单里，"两侧状态不一致"这一类已经清掉了一条完整的**：
不是数据没生成，也不是权限不通，而是**生产侧把一个 Option 序列化成数组、消费侧又把解码异常吞成空态**。
两类问题叠加，才伪装成"管理侧什么都没有"。

### 2.16 登录后落在真实门户了：把根跳转改成"看 cookie"

§4 缺陷 #7 那条（前端 `location = /` 无条件把人送进 demo）修掉了，修法是**按 cookie 分流**，
既保住 demo 展示，又修掉"刚登录也被塞进 demo"这个 bug：

```nginx
location = / {
  if ($cookie_lunanexa_http_enterprise_oidc = "") { return 302 /enterprise/?demo=1; }
  return 302 /enterprise/;
}
location = /enterprise { …同上… }
```

**行为验收**（`curl` 直接看跳转目标）：

| 请求 | 修复前 | 修复后 |
|---|---|---|
| `5002/`（无 cookie） | `302 /enterprise/?demo=1` | `302 /enterprise/?demo=1`（展示照旧） |
| `5002/`（带会话 cookie） | `302 /enterprise/?demo=1` ❌ | **`302 /enterprise/`** ✅ |

**浏览器端到端**（真实 OIDC 登录，CDP 抓的最终地址）：

```
final url: http://106.39.18.146:5002/enterprise/          ← 不再带 ?demo=1
   200 :5002/auth/session
   200 :5002/v1/auth/self
   200 :5002/v1/auth/trial
   200 :5002/v1/auth/sessions
```

**至此"登录后看不到自己数据"这件事的两个成因都清掉了**：
一是 §2.7 那个 JSON 契约（会话解不出来），二是这里这个根跳转（解出来却被送去 demo）。
现在登录后直接落在真实门户、并且渲染真实租户。

顺带记一个操作教训：**这个前门 nginx 的配置挂在 `/etc/nginx/custom/`，不是 `/etc/nginx/nginx.conf`**；
而且在这个环境里 `kubectl exec ... grep -c` 的返回**不可靠**（多次在中途返回 0，
与随后被行为验证为"已生效"相矛盾）。所以判断配置是否生效，
**一律用行为验证（curl 看跳转/状态），不要信 pod 内 grep**。改完记得等挂载同步
（本次首次 reload 就抢在同步之前，白跑一轮）。

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
7. **登录成功会被立刻塞进演示门户（本次新发现，代价最低的缺陷）**：前端 5002 的
   `location = /` 是**无条件** `return 302 /enterprise/?demo=1;`。所以一个刚完成 OIDC 登录、
   带着真实会话 cookie 的用户，落地的第一个页面是 demo 页面；而 demo 模式不联系控制面
   （见 #5 的零请求证据），于是用户看到的是 `org-northstar / 1 / 1 / 2 / CNY 18,420` 这套假数据。
   **这就是"登录了却看不到自己的真实数据"的根因**，修法也很轻：
   `location = /` 在存在有效会话时应当跳真实门户，而不是无条件跳 demo。

## 5. 卡点清单（按修复收益 / 代价排序；多数已由后续轮次修复，保留作为过程记录）

1. ~~**补 `docker.io/lunanexa/postgres:16-bookworm-bb3e1a57` 到 containerd 并让身份库起来。**~~
   **✅ 本次已完成并验证。** 该镜像内容早已在本地（`dockerproxy.net/library/postgres:16-bookworm`，
   主库 `lunanexa-postgres-0` 正用着），只是引用名不同；`k3s ctr images tag` 加别名即可
   （同一 image id `5f71c21b69a79`）。身份库 `1/1 Running`，Keycloak `1/1 Running`。
   教训：`imagePullPolicy: Never` 下，**引用名必须精确匹配**，内容相同不算。
2. ~~**让两个 edge 的镜像引用可解析并重滚**（第 3 跳的前半）。~~
   **✅ 本次已完成并验证。** 结论：这类 edge 是**纯 nginx 反代**（配置只有一行
   `proxy_pass http://lunanexa-identity-gateway:8081`），因此镜像只需"是个能跑的 nginx"，
   不必匹配那个已不存在的构建；`lunanexa-web` 实测就是 nginx 1.27.5。两个别名之后，
   `lunanexa-identity-internal-edge 2/2`、`lunanexa-identity-public-edge 1/1`、
   `lunanexa-identity-edge 2/2`、`lunanexa-enterprise 1/1`、`lunanexa-workbench 1/1` 全部起来了，
   `svc/lunanexa-console-public` 的 Endpoints 也随之填充（5003 的 302 就是它给的）。
   教训：`imagePullPolicy: Never` 下，**引用名必须精确匹配**，内容相同不算；
   但这次证明"名字不同、内容等价"时，先确认该容器是否真的依赖那份构建的差异。
3. **公网明文 HTTP 上，控制台按设计拒绝管理员登录**（第 3 跳剩下的那一个开关）。
   `http://106.39.18.146:5003/` 会渲染出控制台，但写着
   `Administrative login is blocked on public plain HTTP. Use the protected localhost URL or install TLS first.`
   闸门在 `ui/browser_transport/transport.mbt:4-19`，开关是 `cmd/console/index.html:5` 的
   `<meta name="lunanexa-public-http-origin" content="">`（签入为空）。
   **这是部署策略选择，不是 bug**：正确做法是装 TLS；临时做法是把该 meta 填成
   `http://106.39.18.146:5003` 并重建控制台 bundle —— 但那等于关掉"公网明文禁止管理员登录"
   这条安全默认（`docs/PUBLIC_HTTP_TRANSITION.md:180-190` 明确写了明文仍有中间人风险）。
   **这一条留给运维决定，我没有替你按。**
4. ~~**5005 没有 `/auth` location**（第 3 跳后半，企业侧）。~~
   **✅ 本次已修复企业侧并验证。** 做法见 §2.6：前端 5002 的 `/auth/` 改指身份网关、
   网关的 enterprise redirect URI 改到 5002、Keycloak 客户端追加 5002 回调。
   结果：`5002/auth/oidc/start?audience=enterprise` 返回正确的 PKCE 302，
   并且**在浏览器里真的完成了 Keycloak 登录、回调换发了会话 cookie**；5003 操作员无回归。
   **最后一跳本次已修好并验证**：控制面 Pod 缺的是仓库里本来就有定义的 `identity-relay` 旁车
   （`deploy/oidc-browser-ingress-controller-patch.yaml`，从未被应用）。先冒烟、再打进
   Deployment 后，`relay8081` 由 000 变 200，**`/auth/session` 由 401/503 变 200，
   并在浏览器里换出了真实的 `lnxs_` 租户会话**（§2.6）。
   剩下的是**前端启动流程**：页面调了 `/auth/session` 却不再跟进任何 `/v1/` 请求，
   于是仍停在登录门。
5. ~~**登录后看不到真实数据**~~ **✅ 根因已定位**：前端 5002 的 `location = /` 无条件
   `302 /enterprise/?demo=1`，把刚登录的用户直接送进 demo（§4 缺陷 #7）。修法很轻，
   本次只定位未改。
6. **realm `lunanexa` 里没有可用的操作员/企业身份**。原本只有
   `smoke-identity-20260904-1832@example.invalid`（且已绑 TOTP）。本次为验证链路用 admin API
   建了测试用户 `recon-operator@lunanexa.local`（注意两个坑：realm 开了
   `registrationEmailAsUsername=true`，且新用户默认带 `CONFIGURE_TOTP`；口令策略要求
   大写+小写+数字+特殊字符，`length(12)`）。正式投用前应改为真实身份接入。
7. ~~**把 `/auth/oidc/*` 接到身份网关并让端口对齐**~~ **✅ 操作员与企业两侧本次都已完成并验证**：
   `5003/auth/oidc/start?audience=operator` 与 `5002/auth/oidc/start?audience=enterprise`
   都返回带 PKCE 的 302 到 Keycloak，`5006` 的 discovery 也应答，
   并且企业侧已在浏览器里真正完成登录并拿到会话 cookie（§2.6）。
   **剩下的只是 4174（控制台）**：它仍没有 `/auth` 路由，而且公网明文下控制台本就不提供
   SSO 入口 —— 与第 3 条同一个策略开关，一并决定即可。
8. ~~**Keycloak 确认 realm 与客户端**~~ **✅ 已确认并调整**：
   `keycloakrealmimport/lunanexa-public-bootstrap-v1` 已 `Completed`，
   `keycloak/lunanexa-platform-idp` `1/1 Running`，admin API 可查；
   `lunanexa-operator` → 5003，`lunanexa-enterprise` → 5005 **与 5002**（本次追加，
   与网关配置一致）。
9. **修掉那个 JSON 契约不匹配**（现在的主线，也是唯一挡住"登进去"的东西）。
   `/auth/session` 已经返回真实 `lnxs_` 会话，但两侧前端都因为
   `expires_unix_ms : Int64` + `derive(FromJson)` 解不了 JSON 数字而回落登录门
   （§2.7，已用仓库外的临时 MoonBit 包在 `--target js` 上复现出确切报错）。
   两处同构：`cmd/enterprise/main.mbt:9-13`、`cmd/console/main.mbt:202-206`。
   建议按仓库既有先例改成字符串解析，并顺手把 `catch` 里的原因记下来（现在被静默丢弃）。
10. **给订单一条真实可用的创建路径**。这是整条承诺函链的硬前提，两侧的原话都指向它。
11. **统一状态源**：企业侧同一页的三个状态读数必须来自同一份生命周期事实。
12. **收敛前端的令牌注入**（§2.5 发现 4）。`operator-4173-proxy` 的 ConfigMap 里明文写着
    操作员令牌，并被注入到每个 `/v1/` 请求；这意味着**任何能访问 4174/5002 的人都自动拥有
    操作员 API 权限，无需任何登录**。这条建议单独评估（属安全项，且与控制台"要不要登录"
    互相牵连），本次只做记录未改动。

## 6. 要跑通承诺函链路，还缺什么

按目标里的每一步标注本次实测到哪：

| 目标步骤 | 本次实测状态 | 缺什么 |
|---|---|---|
| 企业侧注册企业 | **未达** | OIDC（第 1-3 跳）；`Organization setup` 无成员关系 |
| 选择时间、租期 | **未达** | 向导存在（6 步），但需先有身份；价格见 §10（此处原文写错了归属，已更正） |
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
- **第 3 跳也基本修好了**：先证明 edge 是纯 nginx 反代、`lunanexa-web` 就是 nginx 1.27.5、
  且这些 pod 都钉在管理节点，再打两个镜像别名 —— 一次连锁带起
  5 个 deployment（identity-edge/internal-edge/public-edge/enterprise/workbench）、
  填充了 `lunanexa-console-public` 的 Endpoints，并让 5006 的 OIDC discovery 与
  5003 的 `/auth/oidc/start`（PKCE 302 + Keycloak 登录表单）真正可用。
- **定位到最后一个卡点的确切开关**：公网明文 HTTP 拒绝管理员登录，闸门在
  `ui/browser_transport/transport.mbt:4-19`，开关是 `cmd/console/index.html:5` 的空 meta，
  且 `docs/PUBLIC_HTTP_TRANSITION.md:180-190` 把它定义为部署策略（明文有中间人风险）。
- 管理侧可以用部署自带令牌经控制台自带的开发后备进入，且显示实时集群数据。
- 企业侧填对令牌也只能到 `Not connected` 外壳，且原因是 `loopback_client` 总闸（代码级证据）。
- 链路在"订单"这一步断掉，两侧因此没有共同对帐物（两侧原文互相印证）。
- 演示模式数字与控制面无关（零网络请求实测）。
- 六项状态/反馈缺陷。
- **前端 404 的确切机理**：不是"没有路由"，而是 `location /auth/` 被指向了控制面（§2.5）。
- **"改一行就好"并不成立**：网关的 `host_and_audience` 硬闸（`server.mbt:610`）要求
  Host 是登记过的 5003/5005，所以必须三处联动；loopback 访问 5003 得到 400 就是这道闸。
- **一个授权缺陷**：前端 ConfigMap 明文内嵌操作员令牌并注入每个 `/v1/` 请求，
  4174/5002 因此无需任何会话即可调用操作员 API（§2.5 发现 4）。
- **本次打通到"真登录"这一级并验证**：改了前端 5002 的 `/auth/` 指向、网关的 enterprise
  redirect URI、Keycloak 客户端的回调登记（三处联动），浏览器里完成 Keycloak 登录，
  回调返回 303 并换发 `lunanexa_http_enterprise_oidc` 会话 cookie（CDP 抓的时序在 §2.6）。
- **定位到最后一跳**：`/auth/session` 把 cookie 换成 `lnxs_` 时失败（先 503 后 401），
  网关日志无输出；已排除 relay 缺失（它是控制面 Pod 里的 `runtime-loopback-proxy` sidecar），
  下一步该比对两边断言密钥（§2.6 末段）。
- **定位到"登录后看不到真实数据"的根因**：前端 `location = /` 无条件 `302 ?demo=1`（§4 缺陷 #7）。
- **钉死并修好了最后一跳**：控制面 Pod 缺的是仓库里本就有定义的 `identity-relay` 旁车
  （`deploy/oidc-browser-ingress-controller-patch.yaml` 给了完整定义，只是从未应用）。
  先以冒烟 Pod 验证镜像/参数（`/health` 200），再打进 Deployment —— 控制面 `4/4 Running`，
  `relay8081` 000→200，**`/auth/session` 401/503→200 并返回真实的 `lnxs_` 租户会话**。
  断言密钥两侧同源，不是原因。
- **新定位并确证**：拿到会话后两侧仍停在登录门，根因是一个 **JSON 契约不匹配** ——
  `expires_unix_ms : Int64` 配 `derive(FromJson)` 在 **JS 后端**解不了 JSON **数字**
  （要求字符串形式）。用仓库外临时 MoonBit 包在 `--target js` 上复现出确切报错
  （`Int64::from_json: expected number in string representation`），数字形式必失败、
  字符串形式可解。企业侧 `cmd/enterprise/main.mbt:9-13` 与控制台
  `cmd/console/main.mbt:202-206` 两处同构，且异常都被 `catch { _ => … }` 静默吞掉。

### 9.5 管理侧上架供给没有界面：纯 UI 的链路走不到起点

接 §9.4 的下一步"上架一条机器供给"，去找管理侧的入口，结论很干脆：

**供给侧的写接口存在，但控制台根本没有对应界面。**

```
api/machine_commerce_http.mbt:10    path == "/v1/machine-commerce/operator/offerings"
api/machine_commerce_http.mbt:496   (Post, "/v1/machine-commerce/operator/offerings") => { … }
```

可是：

```
$ grep -c "machine-commerce" cmd/console/main.mbt          -> 0
$ 线上 bundle 里（5,932,739 字节）
  machine-commerce refs: 0
  machine-offerings refs: 0
$ bundle 里所有 /v1/*machine* 路径                        -> 空
```

也就是说**控制台里没有任何页面能发布/管理机器供给**（`Policies` 页只到
"Register a runtime profile"，那是运行时而镜像，不是机器供给）。
把 §9.2 的两条事实合起来，链路**从起点就走不通纯 UI**：

1. 企业侧容量页读 `/v1/portal/self/machine-offerings` → **200 但 `[]`**（§9.2 更正后的事实）；
2. 唯一能把它变成非空的动作（`POST /v1/machine-commerce/operator/offerings`）
   **只有 API，没有界面**。

所以"承诺函链路无法在纯 UI 下开始"不是权限问题、不是配置问题，
而是**管理侧缺少一个供给侧界面**。这正属于本次任务要找的那类卡点，
而且它解释了为什么两条机器类服务都停在同一句话。

### 9.6 企业侧"创建订单草稿"按钮：观察到一次点击无任何反应（未干净复现）

另外记一条**尚未确认**的观察，不要当成结论：在把
`offline-project / offline-service / offline-sla` 三个字段都填上、按钮已从灰变亮的情况下，
点 `Create draft order` **没有发出任何请求、也没有任何提示**（CDP 抓 `/v1/` 流量为空，
页面仍停在 `No commercial orders yet`，也没有出现 "Unable to create the offline order" 那种失败文案）。

代码上是通的：`ui/offline_commerce/offline_commerce.mbt:1221` 的按钮
`on_click=command(emit, CreateOrder)`，`cmd/enterprise/main.mbt:4294` 也有
`Portal(OfflineCommerce(CreateOrder))` 的分支去调 `offline_order_command`。
所以"点了没反应"要么是我这边驱动的问题（这个 SPA 的字段/路由状态在多次命令之间不稳定，
我后来重试时连三个输入框都找不到了），要么是消息没接上。**需要人工点一次来定论。**
我把它标为未确认，避免又像 §9.2 那样先写错再更正。

### 9.7 上架一条供给后，链路往前推进了一格 —— 但卡在"节点没有 region 标签"

§9.5 说供给侧没有界面。为了不让链路停死，**我在界面之外做了唯一一次供给上架**
（这一处**不符合"纯 UI"的要求**，明确标注出来）：

```
POST /v1/machine-commerce/operator/offerings   -> 201
（body 用 MachineOffering 的字段，int64 按仓库惯例发字符串；state=OfferingActive，capacity_total=4）
operator snapshot 之后：offerings: 1 item（之前是 0）
```

**企业侧立刻看到了这条供给**（用门户会话令牌查，200）：

```
GET /v1/portal/self/machine-offerings -> 200 len=774
[{"offering":{"offering_id":"offer-dgx-spark-01","sku":"dgx-spark-gb10",
  "display_name":"DGX Spark (GB10) exclusive node","kind":"BareMachine",
  "accelerator_class":"nvidia-gb10","memory_mib":"131072", …}}]
```

**UI 上也真的出现了**，`Bare GPU → Choose capacity` 从"没有容量"变成一张可看规格与价格的卡片：

```
DGX Spark (GB10) exclusive node
nvidia-gb10
Unavailable            ← 注意这一行
GPU 1 · Memory 128 GiB · Regions cn-north-1 · CNY 0.02 / second
Select capacity
```

**但它是 `Unavailable`，点 `Select capacity` 也没有任何反应。** 根因找到了，
而且是一个"永远不可能满足"的条件：

```moonbit
// api/machine_commerce_reconciler.mbt:48-49
/// Trusted node inventory label used to honor the purchased regional SKU.
let machine_region_label : String = "lunanexa.io/region"
// :53  Missing region labels fail closed; there is no implicit cross-region fallback.
// :84  … &&
//      heartbeat.inventory.labels.get(machine_region_label) == Some(offering.region) && …
```

而**四台节点的标签里根本没有 `lunanexa.io/region`**（完整 dump，第一台 `spark-25e2-3d35c8fd`）：

```
lunanexa.data-classes          = Confidential
lunanexa.gpu.compute-capability= 12.1
lunanexa.gpu.driver            = 580.178.04
lunanexa.gpu.model             = NVIDIA GB10
lunanexa.io/cx7-address        = 192.168.100.10
lunanexa.io/cx7-peer           = spark-3782-feee26eb
lunanexa.io/host-cpu-count     = 20
lunanexa.io/host-memory-mib    = 124608
```

**没有任何一台带 region 标签。** 由于这条是"缺标签即 fail closed"，
`machine_offering_nodes` 对**任何 offering** 都会返回空 → 可用容量恒为 0 →
**所有机器类供给永远 Unavailable，机器订单永远下不了单**。

顺带记下我的供给参数与真实清单的差异（就算 region 问题解决了，这几个也得对齐）：
我发的是 `accelerator_class="nvidia-gb10"`、`memory_mib=131072`，
而节点实际是 **`architecture="nvidia-sm121"`、`memory_total_mib=124608`**。

**所以链路现在的卡点链是完整的、可执行的：**

| # | 卡点 | 证据 | 性质 |
|---|---|---|---|
| 1 | 从未上架过任何供给 | operator snapshot `offerings: 0` | 运维状态 |
| 2 | 供给侧没有界面 | 源码与线上 bundle 里 `machine-commerce` 均为 0 引用（§9.5） | **产品缺口** |
| 3 | 节点没有 `lunanexa.io/region` 标签 | 四台节点标签完整 dump（本节） | **产品/运维缺口**（fail-closed 前提未满足） |
| 4 | 供给参数与真实清单不一致 | `nvidia-gb10` vs `nvidia-sm121`、131072 vs 124608 | 配置错误（我发的这条） |

**第 3 条是关键**：它不是配置我能绕过的 —— 只要节点库存里没有这个标签，
这个平台的机器售卖功能就是**恒不可用**的。

### 9.8 补上 region 标签后，链路第一次走过容量页

§9.7 定位到"没有任何节点带 `lunanexa.io/region`，可用容量恒为 0"。这一轮把这条路走通了
（都是**配置层**改动，改前都备份）：

**① 给四台节点的清单补上 region 标签。** 节点的标签来自各自的 ConfigMap
`lunanexa-node-inventory-spark-*` 里的 `inventory.json`；四份都补上
`"lunanexa.io/region": "cn-north-1"`，并重滚四个 node-agent 让它们重新上报：

```
spark-25e2-3d35c8fd -> cn-north-1
spark-368c-0f2ee8b2 -> cn-north-1
spark-3782-feee26eb -> cn-north-1
spark-57f5-98a504ed -> cn-north-1
```

**② 把供给参数对齐真实清单**（原来 `nvidia-gb10 / 131072` 对不上
`nvidia-sm121 / 124608`）。注意**同 id 更新会 409**（有不可变字段），所以用新 id 发了一条
`offer-dgx-spark-02`（`sku` 也换了 `dgx-spark-gb10-v2`）：

```
operator snapshot: offerings 2
  offer-dgx-spark-01  OfferingActive  nvidia-gb10   ← 旧的对不上
  offer-dgx-spark-02  OfferingActive  nvidia-sm121  ← 对齐后
```

**③ 可用容量立刻从 0 变成 4**（门户会话令牌查）：

```
machine-offerings -> 200
  offer-dgx-spark-01  availability.capacity_available = 0
  offer-dgx-spark-02  availability.capacity_available = 4   ✅
```

**④ UI 上也真的通了。** 这是承诺函链路第一次越过容量这一格：

```
Bare GPU → Choose capacity
  [卡1] DGX Spark (GB10) exclusive node · nvidia-gb10 · Unavailable · … · Select capacity
  [卡2] DGX Spark (GB10) exclusive node · nvidia-sm121 · Available · Memory 121 GiB · CNY 0.02 / second
按卡2 的 Select capacity 之后：
  卡2 变为 "Selected"
  页面出现 "Configure order" 表单：Project / Linux username（"Required for bare …"）
```

**所以"选择时间、租期"这一格现在真的可操作了** —— 下一步就是填 `Configure order`
往下走到 Quote / Contract & payment / Provisioning，那才是承诺函真正出现的地方。

**顺带再记一次那个无障碍缺陷**：两张卡的可见名称完全相同
（`DGX Spark (GB10) exclusive node` 与 `Select capacity` 各出现两次），
我是靠**按索引**才点中第二张的。这在真实使用里意味着用户无法从标签区分两张卡 ——
和 §4 缺陷 #2 是同一类问题，这里又复现了一次。

### 9.9 走到 Configure order，卡在"Review price"静默无反应（找到了代码原因）

§9.8 越过容量页之后，`Configure order` 表单出现，字段是：

```
Project              （预填 trial-project-b131b8c579a5901fe5ea97fe）
Linux username       （必填：小写字母开头，a–z 0–9 _ - ，保留名会被拒）
Region               （Select a region → cn-north-1）
Rental period        （24 hours / 7 days / 30 days，旁注 "0–24 hours allowed"）
Managed model        None — you manage this workspace
Review price / Back
```

**踩到的第一个坑：这些控件是用 `id` 而不是 `name` 定位的**
（`document.querySelector('input[name=self-service-unix-username]')` 取不到，
`getElementById('self-service-unix-username')` 才行；DOM 里 `name` 是 null）。
我前面空跑了两轮就是因为这个 —— 记下来，这个 SPA 的字段既有 `name` 的也有 `id` 的，两种都要试。

**填好之后（三个值都确认写入 DOM）：Project / Linux username=reconuser / Region=cn-north-1 /
Rental period=24，按钮 `Review price` 是 enabled**，点下去：

```
click: clicked
--- /v1/ 流量 ---
（空）
--- 页面 ---
仍停在 Configure order
```

**又是"点了没有任何请求、也没有任何反馈"。** 这回代码上找到了确切原因 ——
`cmd/enterprise/main.mbt:3644-3648`：

```moonbit
Portal(SelfService(RequestQuote)) => {
  if !@enterprise_ui.self_service_configuration_valid(model.portal.self_service) {
    return (model, @rabbita.none)      // ← 静默返回：不请求、不报错、不改状态
  }
  …(next, machine_quote_command(next, emit))
}
```

**即"配置校验不通过"这条分支是静默 no-op**，用户看到的只有"点了没反应"。
（同一函数也用于按钮的 `disabled`，所以正常情况按钮会是灰的；
我这次看到的是 enabled 却无反应，说明**壳里的模型状态与按钮渲染所依据的状态不一致**，
或者我的合成事件只改了 DOM 没进模型 —— 这两者需要一次真人点击来分辨，
我**不当结论**写，只记事实与代码位置。）

**第二个可操作的发现：租期被我的供给参数限住了。**
表单旁注 `0–24 hours allowed`，而 7 days / 30 days 选了也会被这条挡住 ——
因为我发的 offering 里 `maximum_duration_seconds=86400`（24h）。
要支持"选择时间、租期"里更长的时间窗，**供给得重新上架、把上限放大**。
（同 id 更新会 409，要用新 id。）

**租期上限这一条已经解决。** 用新 id 发了 `offer-dgx-spark-03`
（`minimum_duration_seconds=3600`、`maximum_duration_seconds=2592000`，
`billing_quantum_seconds=3600`），门户端确认：

```
offer-dgx-spark-01  avail=0  min=60    max=86400     (24h)
offer-dgx-spark-02  avail=4  min=60    max=86400     (24h)
offer-dgx-spark-03  avail=4  min=3600  max=2592000   (1h–30天)  ✅
```

所以"选择时间、租期"现在**有可选的机器、有 1 小时到 30 天的窗口**，
只差 `Review price` 那一跳。

**至此"选择时间、租期"这一格的现状**：页面能走到、能选机器/区域/时长，
但**受 `Review price` 静默无反应这一条挡住**（代码位置见上）。

#### 补充：用真实鼠标事件复测，并读完了"有效"的判定条件

为了排除"合成 `.click()` 打不到应用"这种可能，我改用 CDP 的真实输入事件
（`Input.dispatchMouseEvent` 的 mousePressed/mouseReleased + `Input.insertText`）重试：

```
Select capacity buttons: 3
clicking last Select capacity: {"x":616.09,"y":1116.375,"disabled":false}
hint: (none)              ← Configure order 表单没出现
duration -> missing
Review price: null
--- /v1/ 流量 ---  (none)
```

**真实点击同样不产生任何请求。** 同时读到了 `self_service_configuration_valid`
（`ui/enterprise/self_service.mbt:466-490`）的完整条件：

```moonbit
guard state.selected_product is Some(product) else { return false }
guard selected_offering(state) is Some(offering) else { return false }
offering.available &&
offering.kind == product &&
offering.regions.contains(state.region) &&
state.project_id.trim() != "" && state.project_id.length() <= 160 &&
state.duration_hours >= offering.minimum_duration_hours &&
state.duration_hours <= offering.maximum_duration_hours && …
```

**所以最可能的触发条件是"`duration_hours` 落在所选 offering 的区间之外"**：
若当时选中的是 24 小时上限的那条供给，而我把时长设成 720（30 天），
这个判定就是 false，于是走到那条**静默 return**。这与观察到的一模一样。

**但我不能据此下结论。** 因为同一个判定也决定按钮的 `disabled`，
按理按钮该是灰的，而我看到的是 enabled —— 这中间的差异（壳状态与渲染状态不一致？
还是我对这个 SPA 的自动化本身就不可靠？）我多次尝试都无法稳定复现完整流程
（同一套动作重跑时，Configure order 表单有时出现、有时不出现），
**所以这一条需要一次真人点击来定论。**

**不过有一条与原因无关、可以直接写下的缺陷**：无论"配置无效"是用户的错还是自动化的错，
**那条分支在界面上不给任何反馈** —— 不提示哪个字段不合格、不显示错误，
用户看到的就是"点了没反应"。这与 §4 里"错误不透明"是同一类，只是这里连错误都没有。
建议：无效时至少高亮不合格字段并给出原因（例如"时长超出该供给允许的 24 小时"）。

## 10. 价目：承诺函与租赁合同两张表不一致，且产品侧已按承诺函执行

**这一节纠正了本报告早先的一处错误归属**：我曾把"日 85 / 周 520 / 月 1900 / 季 5100 / 年 15800"
写成"承诺函附件一"的价目。实际上那是**租赁合同**的附件一，而**承诺函里有它自己的一套**。

### 10.1 两份文件的价目（原文抽出）

**设备使用承诺函 · 附件2** —— `assets/contracts/youthpolicy/undertaking-v1/moonleaf-preview-template.v1.json`
标题「单台设备租金标准 / 折算日租金」：

| 租期 | 最短 | 单台租金标准 | 折算日租金 |
|---|---|---|---|
| 日租 | 1天 | 49元/天 | 49元/天 |
| 周租 | 7天 | 322元/周 | 46元/天 |
| 月租 | 30天 | 1290元/月 | 43元/天 |
| 季租 | 90天 | 3600元/季 | 40元/天 |
| 年租 | 365天 | 13870元/年 | 38元/天 |

正文复述同一单价：「租金按实际使用天数，**以49元/天的标准**据实结算。」

**租赁合同 · 附件一** —— `assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json`
标题「租期档位与价格表（单台，含税）」：

| 租期 | 最短 | 单台租金标准 | 折合日租金 | 适用场景 |
|---|---|---|---|---|
| 日租 | 1天 | 85元/天 | 85元 | 临时模型验证、短期项目测试 |
| 周租 | 7天 | 520元/周 | 74.3元 | 小型开发任务、周度迭代训练 |
| 月租 | 30天 | 1900元/月 | 63.3元 | 月度研发项目、持续推理部署 |
| 季租 | 90天 | 5100元/季 | 56.7元 | 季度级AI项目、长期模型微调 |
| 年租 | 365天 | 15800元/年 | 43.3元 | 全年常态化AI业务、固定研发需求 |

差额（承诺函 − 租赁合同）：日 −36 / 周 −198 / 月 −610 / 季 −1500 / 年 −1930，
承诺函约为租赁合同的 **58%**。两份文件**各自内部自洽**（租赁合同的退租核算表同样硬编码
85元/天、1900元/月），所以这是**两份合同文件之间的对不上**。

### 10.2 产品侧（报价）**已经**按承诺函的价目执行

`commercial/offline/undertaking.mbt:4`：

```moonbit
pub fn undertaking_tariff(unit : String) -> Int64? {
  match unit {
    "day" => Some(4900L)      // 49.00 元
    "week" => Some(32200L)    // 322.00
    "month" => Some(129000L)  // 1290.00
    "quarter" => Some(360000L)// 3600.00
    "year" => Some(1387000L)  // 13870.00
    _ => None
  }
}
```

界面措辞也是这个：「承诺函固定价目（元/台）」「Quote undertaking tariff / 按承诺函价目报价」。
**所以"报价"这条路用的就是承诺函的价格，没有用到 85/520/…。**

### 10.3 真正还留着老价格的地方：**租赁合同文档本身**

```
assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.docx          85×19 520×3 1900×2 5100×2 15800×1
assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.fillable.docx 同上
assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json                  85元/天×8 …
```

其余位置（`docs/`、`ui/`、`cmd/`、`contractdoc/`）**没有**这些老价格 —— 我全仓扫过。

**但这里有一条仓库自订的规矩**（`docs/contracts/youthpolicy-dgx-spark-remote-lease-v1.md`）：

> The retained DOCX is the design and legal-text authority. LunaNexa must **never**
> rewrite, summarize, translate, or extend its clauses.
> A different digest is a new template version and requires a fresh slot and visual audit.

**所以"把合同价格改成承诺函的价目"不是改个常量，而是重新签发这份合同文档** ——
属于法务动作，不由平台自行改写。可行的机械流程是（承诺函模板那份 README 里就是这个管线）：

```
① 拿到一份仅把附件一价格单元格改为 49/322/1290/3600/13870 的新源 DOCX（由你/法务出）
② 按 build-*-template.mbtx 的手法生成新的 fillable（只动 word/document.xml 的对应单元格）
③ moon run cmd/contract-preview-scene --target native -- \
     <新 fillable.docx> assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json <template_id>
④ 更新 contractdoc/youthpolicy.mbt 里 pin 的两个摘要（fillable_sha256 与新模板版本）
⑤ 跑契约测试 + 一次视觉审计
```

**这一步我没有动**：它要改的是"法律文本权威"，而且必须换新的摘要与模板版本号。
需要你定：**由你出新源 DOCX**，还是**要我按上述流程用现有源文件只改价格单元格生成 v2**
（我能在 `word/document.xml` 里精确替换那几个价格，但那等于平台改写了合同，与上面那条规矩冲突）。

## 11. 统一登录路径：用户名+密码 → access token（前提已验证）

### 11.1 你定的方向

「我们暂时没有 tls，路径应该都统一到（用户名-密码）到 access token 到登录。」

也就是说：不再走 OIDC 跳转那一套（它在公网明文下还被前端主动隐藏），
而是**一个入口：输入用户名和密码 → 换到 access token → 已登录**，控制台与企业门户都走它。

### 11.2 前提已验证并打开：Keycloak 直连授权（Resource Owner Password）

先在 Keycloak 上把两个客户端打开直连授权（`directAccessGrantsEnabled`，
改动经 admin API，各返回 204）：

```
lunanexa-operator    : public=False directAccessGrants=False → True   standardFlow=True secret=yes
lunanexa-enterprise  : public=False directAccessGrants=False → True   standardFlow=True secret=yes
```

然后用真实用户名密码**实测直连授权**（两个 audience 各一次，凭各自的 client secret）：

```
lunanexa-operator:    OK  azp=lunanexa-operator    user=recon-operator@lunanexa.local
lunanexa-enterprise:  OK  azp=lunanexa-enterprise  user=recon-operator@lunanexa.local
```

返回体同时带 `access_token` 与 `id_token`（`expires_in=300`）。
**结论：用户名+密码 → access token 这条路在本部署上成立，且两个受众都成立。**

### 11.3 要落成的形态（设计，尚未实现）

关键点是：**浏览器不该自己去拿 Keycloak 的 token**，否则等于把 client secret 放进前端。
统一路径应当由身份网关承接下来：

```
浏览器  ──POST /auth/password{username,password,audience}──▶  身份网关
                                                              ├─ 用对应 client 的 secret 向 Keycloak 做直连授权
                                                              ├─ 校验 id_token / 取到 subject
                                                              ├─ 走**与回调完全相同**的发会话路径
                                                              │  （issue_controller_session + session store + cookie）
                                                              └─ 返回与 /auth/session 相同的 JSON
浏览器  ◀── {session_token, csrf_token, expires_unix_ms} ────
```

好处是：**会话仍是同一种 `lnxs_` 会话**，下游（控制台、门户、`/v1/` 鉴权）一行都不用改；
变的只是"怎么拿到它"。

要改的地方：

| 位置 | 改动 |
|---|---|
| 身份网关 | 新增 `POST /auth/password`：直连授权 + 复用现有发会话逻辑（新代码 + 测试） |
| 控制台 4174 | 把登录门换成"用户名+密码"表单，提交后存下返回的 token（替换现在那套 operator/audit 令牌框） |
| 企业门户 5002 | 同样换成"用户名+密码"表单（替换现在的 scoped token + subject 框） |
| 镜像/打包 | 网关要重建重滚（走 SOP §5.1）；两个前端要重建 bundle |

### 11.4 必须说清的安全事实

按你的决定**暂时不上 TLS**，那么**用户名和密码会以明文经过网络**。
这在安全上不弱于现在这套（现在公网明文下那条 OIDC 跳转也一样暴露），但它意味着：

- 这套路径**只应作为过渡**，一旦上 TLS 就应把直连授权关掉（`directAccessGrantsEnabled=False`），
  回到 authorization-code + PKCE；
- 网关侧应当**只对 session 做内存持有**（沿用现在的"凭据不进 URL/存储"约定），
  并给直连授权加限速/失败计数，避免被当作密码爆破入口。

这两条我会在实现时一并做，**但"明文凭据"这件事本身是你已经拍板的取舍**，我按你的决定执行。

### 11.5 已实现并已在真实集群验证（2026-09-22）

11.3 那张表全部落地并上线，逐项都有实测证据：

| 项 | 状态 | 证据 |
|---|---|---|
| 网关 `POST /auth/password` | 已上线 | 新镜像 `acceptance/identity-gateway@sha256:09f25011…`；`cmd/identity-gateway` 单测 30/30 |
| 操作员账户 | 已建 | Keycloak 里 **`wlc`**（`registrationEmailAsUsername` 已关，所以用户名不再是邮箱）；控制面账户 `account-fe3ed0627ed85ce6e51cf621` 角色 `[PlatformOperator]` |
| 控制台登录门 | 已上线 | 浏览器实测：填 `wlc` / `Wlc123!@1234fsc` → `POST /auth/password 200` → 控制台渲染（`Account session active`、节点 4/4） |
| 门户登录门 | 已上线 | 浏览器实测：同账户 → `/auth/password 200` → 门户渲染 |
| 门户自助注册 | 已上线 | 浏览器实测：填邮箱/名称/密码 → `POST /auth/register 201` → 门户渲染（试用租户、`Your trial is ready`） |
| 企业侧账户自动开通 | 已验证 | 注册后控制面出现该邮箱的账户，角色 `[EnterpriseUser]`，状态 Active |

顺带确认的三条边界：

- **操作员主机拒绝注册**：`POST /auth/register` 带 operator 受众 → `403 registration-audience-rejected`。
- **重复邮箱** → `409 email-taken`；**弱密码** → `400 password-rejected`（判定权在 Keycloak 的 realm 口令策略，网关不自己定规则）。
- **静态操作员令牌已按设计退役**：一旦出现带 `PlatformOperator` 的账户，
  `LUNANEXA_RETIRE_BOOTSTRAP_OPERATOR_TOKEN` 就会让静态令牌失效——
  实测 `/v1/accounts` 用静态令牌返回 401 `valid operator authority is required`，
  用 `wlc` 的会话返回 200。**这不是故障，是预期**，但它意味着统一登录必须先可用。

### 11.6 与本次一起改掉的部署侧前提（不改这些，前端一直是灰的）

- **4174 的 `/auth/` 原本指向控制面**（带一个静态 bearer），统一登录后必须指向身份网关，
  并把 `Host`/`Origin` 改写成 operator host（`106.39.18.146:5003`）。
- **`lunanexa-public-http-origin` meta 是空字符串**。没有它，`endpoint_allowed` 在公网明文下一律为 false，
  于是每个输入框和按钮都是 `disabled`——现象就是"登录页什么都没反应"。
  新增 `scripts/deploy/render-public-http-origin.py` 在构建 bundle 后把它渲染成**各页面自己的** origin。
- **门户 landing 默认进演示态**（无 cookie 时 302 到 `/enterprise/?demo=1`），真实注册/登录表单永远看不到。
  已改为直接 302 到 `/enterprise/`。
- **企业侧登录门原本只认 loopback**（`hostname === "localhost" || "127.0.0.1"`），
  所以它在 `http://106.39.18.146:5002` 上永远不可用。已改为与控制台同一条
  `ui/browser_transport` 策略；开发令牌回退仍保持 loopback-only。

## 8. 未验证

- 真实 OIDC 登录与首次登录建账户/受限体验。
- 真实订单提交、管理侧审批、DOCX/PDF 生成与下载、签署盖章、扫描件上传与复核。
- 权限实际开通后企业侧是否真正拿到权限。
- 管理侧的 CPU/内存等指标在浏览器中的渲染（本次控制台是实时数据，但没有逐项核对指标卡）。

本次对帐的记账口径：**"能点进去并拿到实时数据"才算一步通了**；只有页面渲染、数据来自
本地夹具或本地会话的，不计为通。

## 9. 承诺函链路的两侧实操记录

地基（身份、会话、两侧数据显示）修好之后，开始按目标里的顺序**真的点按钮**。
下面是本次走到的位置。每一条都记"按了什么 → 看到什么"。

### 9.1 企业侧：注册企业（第 1 步）——自动满足

企业侧用真实 OIDC 登录后，会话条即为
`subject-b131b8c5… · trial-org-b131b8c5… · secure browser session`。
进 `Get started` 走 6 步向导（1 Service / 2 Organization / 3 Capacity / 4 Quote /
5 Contract & payment / 6 Provisioning），选服务后到第 2 步，页面直接显示：

```
ORGANIZATION
Organization ready
This order will be owned by your active organization. Tenant and subject identifiers
are derived from your signed-in session.
Organization  trial-org-b131b8c5…
Tenant        trial-tenant-b131b8c5…
Back  Continue
```

即**组织不是"填表注册"，而是从已登录身份派生**（首次 OIDC 登录时建的受限试用组织）。
这一步没有可填字段，点 `Continue` 即通过。**这是目标里"用户一方注册企业"在本部署的实际形态。**

### 9.2 企业侧：选择时间、租期（第 2 步）——卡在容量页

按 `Continue` 到第 3 步 Capacity。**两条机器类服务都走不下去**：

| 选的服务 | 容量页显示 |
|---|---|
| Bare GPU（第 3 张卡） | `No capacity available` / `Try another service or refresh availability. No order has been created.` |
| Dedicated MaaS（第 2 张卡） | 同上 |

点 `Refresh availability` 无效（仍是同一句）。页面底部另有 `Back` 与 `Integration contract`。

**卡点抓到了确切那一条请求**（该步骤轮询 `machine-offerings`）。

⚠️ **这里我一开始测错了，下面是更正后的结论。** 我第一次是用页面里一个**裸 fetch** 去问的，
得到：

```
GET /v1/portal/self/machine-offerings -> 403
{"error":{"code":"MachineOrderAccessDenied","message":"machine purchasing role is required"}}
```

我据此写了"不是没容量，是没购机角色"。**这个结论是错的**，因为我漏了一件事：
前门 nginx 会给**没有 Authorization 的请求**注入操作员令牌（那正是 §2.9 改的 map 的
"没带才回落"分支）。所以裸 fetch 是以**操作员身份**问的，403 说的是操作员没有企业成员资格，
**不是**这个试用账户没有角色。

**用门户自己的会话令牌重测（也就是应用真正在做的事）：**

```
GET /v1/portal/self/machine-offerings -> 200  len=2  ::  []
GET /v1/portal/self/organizations     -> 200  ::  …trial-org-b131b8c5… state=Active…
```

**200，而且就是一个空数组 `[]`。** 所以：

1. **真实卡点：机器供给目录是空的** —— 没有任何 active offering。
   UI 那句 `No capacity available` 是**如实**的，不是把权限错误说成没容量。
2. 之前那条"UI 把 403 渲染成没容量"的**反馈缺陷不成立**，我在报告里撤回它。
   （§4 里"错误不透明"那几条仍然成立，但这一条不是。）

**方法论教训（记下来，因为这次害我写错一轮）**：在这套前端上，
**裸 `fetch` 与"应用自己发出的请求"不等价** —— 裸 fetch 会被注入操作员令牌。
要判断应用的真实状态，必须复刻它自己的凭据（从 `/auth/session` 取会话令牌再带上），
或者干脆看 UI。**不要用裸 fetch 的返回码去推断会话态的问题。**

**因此这一步的下一步不是"授权"，而是"上架供给"**：管理侧需要真正发布机器供给
（active offering），企业侧容量页才可能从 `[]` 变成可选的机器。
这也解释了为什么两条机器类服务都是同一句话 —— 目录为空，与服务类型无关。

### 9.3 旁路观察：Shared MaaS 走的是另一条路

第 1 张卡（Shared MaaS）不进订单流程，而是直接给 `Create API key`
（配合首页那条 `FREE SHARED-INFERENCE TRIAL / 23h remaining · Requests 0/100 · text.qwen`）。
也就是说**试用期只开放共享推理这一条**，机器类服务需要另外的授权。

### 9.4 管理侧：可以看到"谁来开通、怎么开通"

管理侧 `Users & access` 页（§2.15 已确认能读出真实数据）带一个
`GUIDED SETUP / Create WebIDE access` 流程，页面原话：
"LunaNexa prepares the account, membership, workspace profile, Developer grant,
and requested compute lease as one resumable package"，分 4 步：
`1 Person & organization → 2 Review access → 3 MasterLease → 4 Enable WebIDE`，
字段有 `Display name / Work email / Organization / Tenant / Identity provider`。

**这看起来就是"客户越过试用、拿到真实授权"的那条管理侧路径**，也正是本次
"两侧对帐"里管理侧该按的按钮。**下一步就从这里继续**：
用它在管理侧把账户配置成有购机/工作区权限，然后回企业侧重新走容量页，
看 `machine-offerings` 是否从 403 变成 200。

---

## 12. 第二轮 UI 走查（2026-09-22 下午）：纯浏览器，逐步记录

§2–§9 是**第一轮**（当时登录还走 OIDC/令牌框）。这一轮的前提变了：统一登录已上线
（§11.5），承诺函/合同两条路线已可选（§11.6），企业侧可自助注册。所以整条链要重新走一遍。

**方法**：一个 CDP 驱动脚本（`walk.mjs`）长期持有两个标签页——`portal`（企业侧 5002）与
`console`（管理侧 4174）——每条命令只做一件事：打开页面、按标签点某个按钮、在下拉里选某项、
在输入框里打字。每一步都记录：点到的**确切标签**、点击前后的**控件清单（含 disabled）**、
页面上的**提示文本**、页面自己发出的**网络请求**、以及截图。下面每一步的"按下"都指这个。

### 12.0 结论与堵点总表（先看这个）

**一句话结论**：整条承诺函链在**第 2 步就被一道设计上的生产闸门挡住**，
所以第 3–7 步在这台机器上**走不到**；闸门之前的部分（注册企业、选租期、管理侧开通权限）
都已经用真实浏览器走通，并在走的过程中修掉了四个会挡住真实使用的缺陷。

**八个步骤的实际状态**

| 步 | 内容 | 状态 | 卡在哪 |
|---|---|---|---|
| 1 | 用户一方注册企业 | ✅ 通 | — |
| 2 | 选择时间、租期 | ⚠️ **一半** | 选档位已通（企业侧与管理侧现在共用同一份档位表，§12.9）；但管理侧"按承诺函价目报价"被 503 挡住（§12.4） |
| 3 | 拉起承诺函 | ⛔ 不可达 | 需要"已有承诺函报价的订单"，而报价就是第 2 步被拒的动作 |
| 4 | 管理侧确认、执行 | ⛔ 不可达 | 同上 |
| 5 | 进入线下流程 | ⛔ 不可达 | 同上 |
| 6 | 重新上传录入登记 | ⛔ 不可达 | 同上 |
| 7 | 开通权限 | ✅ 通（**真实身份**，§12.17） | 承诺函那条路不可达；但 `Users & access → Create WebIDE access` 独立可用，§12.10 用合成身份走过，§12.17 用真身份又走了一遍（`…:enable → 200`） |
| 8 | 企业侧得到权限 | ⛔ **实际上没拿到** | 管理侧显示 `Ready`，但企业侧**一点变化都没有**——原因是开通落到了客户会话解析不到的租户上（堵点 J，§12.17） |

**堵点总表（按严重度）**

| # | 堵点 | 严重度 | 状态 |
|---|---|---|---|
| A | 企业侧"创建订单草稿"点了没反应，并且**把整个 SPA 冻住**（`crypto.randomUUID` 在明文 HTTP 下不存在，抛出的原生异常打断了运行时的消息循环） | 致命 | ✅ 已修并验证（§12.2） |
| B | offline commerce 这条路**没有任何失败反馈通道**（状态里有 error/success，视图从不渲染） | 严重 | ✅ 已修并验证（§12.2） |
| C | 门户 `index.html` 被浏览器缓存，**bundle 更新到不了用户**（本轮实际撞上） | 严重 | ✅ 已修并验证（§12.2） |
| D | **同一账户第 9 次登录（不登出）就被完全锁死**，控制台和门户同时进不去，且没有任何 UI 能撤销那些会话 | 严重 | ✅ 已修并验证（§12.3） |
| E | **整条承诺函链的闸门**：`/v1/offline-commerce/operator/quotes → 503 OfflineCommerceNotReady`，17 条 blocker code，能力集为空 | **决定性** | ❌ **不修**：这是 `docs/OFFLINE_COMMERCE.md` 要求的状态，伪造签名就绪证明等于删掉闸门（§12.4） |
| F | 试用租户被给了**永远只能 403** 的动作（`Review price`），提示却是"重试" | 中 | ✅ 已修并验证（见 §12.14） |
| G | 试用租户的租期上限 24 小时只写在下拉下方一句静态小字里 | 轻 | ✅ 已修并验证（见 §12.15） |
| H | `Provider subject` 字段**没有任何说明**，而平台里**没有任何界面显示**一个人的原始 IdP subject（各处只显示派生指纹），操作员必须去 Keycloak 管理台抄，且抄错会静默给别人开通账户 | 中 | ✅ 已修并验证（见 §12.16） |
| I | 确认框只写 `week × 1`，**不显示金额**——"冻结不可变报价"这种动作看不到价格 | 轻 | ✅ 已修并验证（见下） |
| J | 开通权限时 `Organization` / `Tenant` 是**手填自由文本**，而客户门户用的是他自注册时的那一套（`trial-org-…` / `trial-tenant-…`）。填不一样，开通照样 `200`、管理侧照样显示 `Ready`，但**落在客户会话解析不到的租户上**，企业侧完全看不到。根因（§12.19）：开通包建的"组织"**在商业平面里不存在**，所以客户端的组织列表里没有它，客户既看不到也切不过去 | **严重**（挡死第 8 步） | ⚠️ **绕行已可见并验证**（§12.18）；**根因未修**——补建商业组织 / 让它能被选中，都要你定产品语义（§12.19） |

**修掉的四个（A–D）都在关键路径上**：不修 A，企业侧连订单都建不出来；不修 B，任何失败都表现为"按钮坏了"；
不修 C，后面所有前端修复都到不了浏览器；不修 D，登录九次之后整条链连入口都没有。
F、G、H、I 是走查中撞到的体验/可核对性缺陷，也都修了。**J 做了绕行**（§12.18：把既有租户
列出来，让操作员照抄），但**根因没修**——§12.19 查明开通包建的组织在商业平面里不存在，
所以客户既看不到也切不过去；补建组织或让它能被选中都要先定产品语义。
**E 和 J 的根因是仅剩的两个开着的**：E 要真实签名（不是代码问题），J 要你定产品决定。

### 12.1 走查步骤与结果（截至本轮结束）

| # | 侧 | 按下的东西 | 结果 |
|---|---|---|---|
| 1 | 企业 | 登录页 → `Register a new account` → 邮箱/名称/密码 → `Create account` | ✅ `POST /auth/register 201` → 门户渲染（试用租户） |
| 2 | 管理 | 登录页 → 用户名 `wlc` + 密码 → `Sign in` | ✅ `POST /auth/password 200` → 控制台渲染（节点 4/4） |
| 3 | 企业 | 导航 `Orders & documents` → 填 `Project ID` → `Create draft order` | ❌ **第一次：完全无反应**（见 12.2） |
| 3′ | 企业 | 同上（修复后） | ✅ `POST /v1/offline-commerce/self/orders 201` → 出现 `offline-order-0f50a176-…`，状态 `Draft`，并显示 "Draft order created. Pricing and offline controls remain pending." |
| 4 | 管理 | 待做：`Offline commerce` 里选租期并冻结报价 | ⏳ |
| 5 | 企业 | 待做：`Contract forms` → 选"设备使用承诺函" → 关联订单 → `Prepare document` | ⏳ |
| 6 | 企业 | 待做：`Save information` → `Review and confirm` → `Generate exact DOCX + PDF` | ⏳ |
| 7 | 企业 | 待做：`Upload signed scan` → `Submit for Party A approval` | ⏳ |
| 8 | 管理 | 待做：`Contract documents` → `Review & approve` | ⏳ |
| 9 | 管理 | 待做：`Register signed evidence` / 开通权限 | ⏳ |
| 10 | 企业 | 待做：确认拿到权限 | ⏳ |

### 12.2 本轮抓到的堵点（按严重度）

#### 堵点 A（致命）：企业侧"创建订单草稿"点了没反应，并且把整个 SPA 冻住

- **现象**：`Create draft order` 按钮是 enabled 的，点下去**没有任何网络请求、没有任何提示、页面不变**。
  更糟的是**此后整个页面再也不响应任何点击**（包括导航和 `Refresh`），直到手动刷新。
- **定位**：用 CDP 打开 `Runtime.exceptionThrown` 抓浏览器自己的异常，得到：

  ```
  TypeError: crypto.randomUUID is not a function
      at random__identifier (enterprise.js)
      at create__offline_order (…)
  ```

  `crypto.randomUUID` **只在 secure context 存在**。本部署是明文 HTTP + 可路由地址，
  所以 `isSecureContext === false`、`crypto.randomUUID === undefined`。
- **为什么会冻住**：这个 TypeError 不是 LunaNexa 的 `raise` 错误，它是原生 JS 异常，
  会穿透命令的 `catch`；而命令是在运行时的消息 drain 循环里执行的，异常打断 drain，
  循环重入标志留在"正在 drain"状态 → **之后所有消息都被丢弃**。
  页面停留在最后一帧，看起来就是"按钮坏了"。
- **修复**：`random_identifier` 改用 `crypto.getRandomValues`（不需要 secure context），
  并加 `Math.random` 兜底，让这个函数**永不抛异常**。控制台与 workbench 用的同一个函数，同样修了。
- **验证**：新注册的企业在浏览器里点 `Create draft order` → 订单创建成功，
  id 是真正的随机 UUID（`offline-order-0f50a176-3fdd-466d-9a53-ddd08ba1c48f`）。

#### 堵点 B（严重）：这条路线**没有任何失败反馈通道**

`ui/offline_commerce` 的状态里有 `error_message` / `success_message`，但**视图从来不渲染它们**
（`ui/contract_documents` 是渲染的）。所以任何被正确转换的失败也都表现为"按钮没反应"。
已补上 `error_message` / `success_message` / `loading` 三处渲染（`role=alert` / `role=status`）。

#### 堵点 C（严重）：门户 HTML 被浏览器缓存，bundle 更新到不了用户

5002 的 `/enterprise/` 没有任何缓存指令，`index.html` 会被缓存；而 HTML 里带着
`enterprise.js?v=<digest>`，于是**新 bundle 部署后用户仍加载旧的那份**。
本轮就实际撞上了：镜像已更新，页面仍在跑上一个 digest。
已改为 `location = /enterprise/index.html` 上 `Cache-Control: no-store`（控制台页面早就是这么做的）。

#### 堵点 D（已修，属登录链路）：会话数上限把账户锁死

见 §12.3。**同一账户累计 9 次登录（不登出）就会被完全锁死**，控制台和门户同时进不去，
而且没有任何 UI 能撤销那些会话——因为撤销入口就在进不去的登录之后。

### 12.3 与走查同时修掉的两处（否则走不到第 3 步）

1. **会话上限改为淘汰最久未用**（`account/store.mbt`）。原来第 9 次登录直接 `raise`，
   经控制面 400 → 网关 503 `identity-session-unavailable`，浏览器只看到"网关拒绝了本次登录"。
   现在是**淘汰最久未用的一条会话**再签发，上限仍然成立，最新凭据永远可用。
2. **网关在拒绝会话交换时把状态码打到 stderr**。浏览器仍然只知道
   `identity-session-unavailable`，但运维日志里现在有 `HTTP 400 {"code":"AccountRejected"}`，
   不用再去猜 relay / provider / 数据库。

### 12.4 决定性卡点：整条承诺函链在**第 2 步**就被一道**设计上的生产闸门**挡住

管理侧 `Offline commerce` 页，选中企业侧刚建的那张 `Draft` 订单，把租期选成
`7 days · 322`，点 `Quote undertaking tariff` → 弹出确认框：

```
CONSEQUENTIAL ACTION
Freeze this immutable quote?
The price, validity window, terms digest, service, and SLA become immutable for this quote revision.
offline-order-0f50a176-… · week × 1
[Go back]  [Confirm with this evidence]
```

点 `Confirm with this evidence` → **`POST /v1/offline-commerce/operator/quotes 503`**，
控制台提示：

> Unable to complete the operation: Offline commercial action failed:
> **verified offline-commerce deployment capabilities are required**

企业侧同一时刻的表现（`Contract forms` 页）是**正确的、诚实的**：

> **No eligible new order is available. Ask Party A to confirm the fixed tariff, or reopen the existing packet below; revisions do not need a second order.**

也就是说：企业侧那条承诺函只能挂在**已经有承诺函报价的订单**上（`undertaking_order_refs`），
而报价正是上一步被 503 拒掉的动作。所以链条断在这里：

| 步 | 状态 |
|---|---|
| 1 注册企业 | ✅ 通 |
| 2 选择租期 / 冻结报价 | ❌ `503 OfflineCommerceNotReady` |
| 3 拉起承诺函 | ⛔ 不可达（没有已报价的订单可挂） |
| 4 管理侧确认执行 | ⛔ 不可达 |
| 5 进入线下流程 | ⛔ 不可达 |
| 6 重新上传录入登记 | ⛔ 不可达 |
| 7 开通权限 | ⛔ 不可达 |
| 8 企业侧得到权限 | ⛔ 不可达 |

**闸门是什么**：`GET /v1/offline-commerce/operator/readiness`（管理侧会话读，200）：

```json
{"status":"OfflineCommerceAdaptersPending","capabilities":[],
 "blocker_codes":["ReadinessCapabilitySetInvalid","ApprovedLegalTemplatesPending",
 "ObjectStoragePending","MalwareScannerPending","OoxmlWorkerPending",
 "MoonLeafPdfRendererPending","SpreadsheetFormulaEnginePending","CjkFontsPending",
 "MachineCallbackIdentityPending","EntitlementAuthorityPending",
 "FinanceLegalPolicyPending","ReadinessEvidenceExpired",
 "ReadinessTransferAdapterUnavailable",
 "ReadinessArtifactDispatcherHeartbeatStale","ReadinessArtifactDispatcherSuccessStale",
 "ReadinessEntitlementDispatcherHeartbeatStale","ReadinessEntitlementDispatcherSuccessStale"]}
```

**这不是 bug，是设计**，而且仓库文档写得很明确：

- `docs/OFFLINE_COMMERCE.md`：「Deployment readiness is supplied only through the signed,
  bounded JSON file at `LUNANEXA_OFFLINE_COMMERCE_READINESS_PATH`, verified with
  `LUNANEXA_OFFLINE_COMMERCE_READINESS_SECRET`. … **Omitting both variables is supported
  and intentionally reports `OfflineCommerceAdaptersPending`** … Initiating side-effect
  routes return `503 OfflineCommerceNotReady` with blocker codes.」
- 同一文档的 Production readiness gates 一节列出必须先证明的十项（双语法律模板 + 不可变哈希、
  S3 兼容对象存储与租户隔离、恶意内容扫描、文档 worker 固定镜像、MoonLeaf DOCX→PDF 渲染与
  逐页视觉回归、XLSX 公式重算、与人类运维权限分离的签名回调身份 …），并总结：
  「**Until these gates pass, readiness must show `OfflineCommerceAdaptersPending`;
  the platform may demonstrate state transitions locally but must not represent the generated
  packet or uploaded evidence as legally executed or financially settled.**」
- 本集群里 `lunanexa-offline-commerce-readiness` 这个 Secret 的内容就是字面量 `pending`
  （`scripts/deploy/generate-management-secrets.sh:47` 就是这么写的），
  而且**全集群没有任何一个 Pod 挂载 `LUNANEXA_OFFLINE_COMMERCE_READINESS_PATH`**。

**所以我不会去伪造那份签名就绪证明**：它存在的意义正是阻止一个半配置的部署签发有法律效力的文件，
伪造它就等于把这道闸门本身删掉。要走通第 2–7 步，需要**运维/法务/财务先真实证明那十项能力**
（并让 artifact / entitlement 两个 dispatcher 跑起来、留下心跳与成功回执），再签出就绪文档。

### 12.5 这一步两侧的显示/反馈是否合格

| 观察点 | 结论 |
|---|---|
| 管理侧点了确认后有没有反馈 | ✅ 有：顶部 notice 明确写"Unable to complete the operation: …"，`Working…` 也出现过 |
| 反馈里有没有**可操作**的信息 | ❌ 没有。真正的 17 条 blocker code 在 503 响应体里，**UI 一个字都没显示**，操作员无法知道缺什么 |
| 操作员能不能**事先**看到这条流水线没就绪 | ⚠️ 部分能：Overview 的 `Production acceptance gate` 卡片里列了 "Offline commerce pipeline · Action required"，但那张卡片**没有链接/按钮可以展开**，看不到具体缺哪几项 |
| 企业侧在被挡住时说了什么 | ✅ 说得很对：指出应由甲方确认固定档位报价；没有假造出可选的订单 |
| 企业侧那条路线选择器 | ✅ 正确：承诺函可选，传统合同显示为 `Traditional rental contract · bilateral execution (temporarily unavailable)` 且不可选（§11.6 的开关生效） |
| 管理侧 `Contract documents` 页在被挡住时说了什么 | ✅ 干净：`TASK INBOX 0/0/0` + **"No contract task is waiting for you."**，`OPERATING VIEW` 全 0，资料包区写 **"No contract packet yet — A packet is created from an approved order; no blank or invented contract is generated."**（与客户侧同一句）。**没有死按钮**：没东西可点，也说明了为什么 |
| 价目是否与 §10 一致 | ✅ 下拉选项原文：`1 day · 49 / 7 days · 322 / 30 days · 1290 / 90 days · 3600 / 365 days · 13870` |

### 12.6 企业侧其实有**两条**租赁路径，只有一条是承诺函

走到这里才看清结构：企业侧 UI 上有两条互不相干的租赁路线。

| 路径 | 入口 | 租期口径 | 状态 |
|---|---|---|---|
| **自服务机器订单** | `Get started` → 选服务（Call a model API / Deploy a private model endpoint / Rent a GPU workspace）→ `Choose capacity` → 选容量 → 填 Project / Linux username / Region / **Rental period** → `Review price` → `SIGNED QUOTE` → `Contract & payment` → `Provisioning` | `24 hours / 7 days / 30 days`（**按秒计价**，`CNY 0.02 / second`） | 页面能走到报价，但**试用租户会被 403 挡住**（见 12.7） |
| **线下商务订单** | `Orders & documents` → `Create draft order` → 运营侧 `Quote undertaking tariff` | 承诺函档位 `1 day 49 / 7 days 322 / 30 days 1290 / 90 days 3600 / 365 days 13870`（**按台**） | 卡在 §12.4 的就绪闸门 |

**本任务描述的"承诺函链"是第二条**。第一条的租期是"小时/天"、按秒计价，和承诺函的
"日/周/月/季/年、按台固定价"不是同一件事。这一点值得写清楚，因为从企业侧首页看，
两条路长得像同一件事的两个入口。

### 12.7 自服务路径上的两个堵点

**堵点 F（试用租户被给了永远走不通的动作）**

`Get started` → `Rent a GPU workspace` → 选容量 → 填 Project / Linux username / Region →
`Rental period` 选 `24 hours` → `Review price` 变成 enabled，点下去：

```
POST /v1/portal/self/machine-quotes  →  403
```

页面提示：

> Operation: The action failed. Refresh and retry; if it persists, contact your operator
> with the action and time. **Sensitive technical details are hidden.**

但控制面的真实原因是 `403 MachineOrderAccessDenied`「**lease requester role is required**」
（`api/machine_commerce_http.mbt:641`）——**试用租户的 membership 里没有 `LeaseRequester` 角色**。
也就是说：这个按钮对试用账号**永远不可能成功**，而界面既没有禁用它，
也没有把"缺角色"这件事说出来，反而让用户"重试"。
按 §9.3 的记录，试用期本来就只开放共享推理，所以限制是设计，**问题是反馈**。

**堵点 G（租期上限只写在说明小字里）**

`Rental period` 下拉有 `24 hours / 7 days / 30 days` 三项。选 `7 days` 或 `30 days` 时
`Review price` 直接变灰，页面上唯一的解释是下拉下方那句静态小字 **"0–24 hours allowed"**；
选回 `24 hours` 按钮立刻可用。也就是说试用租户的租期被限制在 24 小时内，
但界面上**没有说这是试用限制**，也没有把不可选的两项标出来。

### 12.8 本轮仍未验证 / 未做

> 本节是**当时那一轮的快照**。其中"确认框不显示金额"已由 §12.13 修掉，
> "第 8 步没走"已由 §12.10 补上，"`Provider subject` 无法核对"已由 §12.16 修掉。
> 仍然成立的只有：第 3–6 步被生产闸门挡住（§12.4），以及租期选择权在运营侧这一点。

- 第 3–7 步（承诺函生成、管理侧批准、登记签署证据、开通权限）**在当前部署上不可达**，原因见 §12.4。
  要在真实节点上走完，需要先满足那十项生产闸门并签出就绪文档——这是运维/法务的决定，不是代码问题。
- 承诺函 DOCX/PDF 到底能不能生成、生成物是否分页正确、扫描件上传与复核，都没有实测。
- 第 8 步（企业侧拿到权限）**还有一条不经过 offline commerce 的路**：
  管理侧 `Users & access` 的 `GUIDED SETUP / Create WebIDE access`（§9.4），
  以及企业侧 `Get started` 的服务选择。这条**本轮没走**，是下一步。
- 管理侧 `Offline commerce` 的租期选择是**运营侧**动作（`operator_actions`），
  不是企业侧动作；也就是说"用户选择时间/租期"在当前实现里是**甲方确认固定档位报价**，
  企业侧只能提需求。这一点与原任务描述的顺序不同，需要确认是否即为预期。
- 确认框里只写 `week × 1`，**不显示金额**；"冻结不可变报价"这种动作不显示价格，是个体验缺口。

### 12.9 按"两侧必须共享同一个租期档位选择"改掉的东西

原先两边各有一套、而且对不上：

- **运营侧**：`ui/offline_commerce` 里**硬编码**了五个 `<option>`（1 day 49 / 7 days 322 / …）；
- **企业侧**：承诺函这条路**根本没有档位选择**，门户上唯一的租期选择是自服务向导里的
  `24 hours / 7 days / 30 days`——那是按秒计价的另一条商务路线（§12.6）。

于是企业侧无法提出一个运营侧能报的档位，链条在第 2 步就接不上。

**改法**：

1. **一处定义**。`commercial/offline/undertaking.mbt` 新增
   `pub let undertaking_term_tiers : Array[UndertakingTermTier]`（unit / days / minor_units），
   并让 `undertaking_tariff`、`undertaking_term_days`、`undertaking_quote_term` **都从它派生**，
   不再各自重述那五个数字。
2. **两侧都渲染它**。运营侧的价格下拉改成遍历这个列表；企业侧 `Orders & documents` 的
   "配置新订单"表单**新增** `租赁档位 / Rental tier` 下拉，也遍历同一个列表。
   档位的文案只有一处：`ui/offline_commerce.undertaking_tier_label`。
3. **选择会传到对面**。`CommercialOrder` 新增 `requested_undertaking_term`，
   由客户下单时带上（`OfflineOrderIntent.requested_undertaking_term`）。
   它是**请求而不是价格**：报价仍由运营侧冻结，文件里写的仍是冻结后的报价。
   未知档位直接 `400 InvalidTerm`，不落库。
4. **运营侧默认跟随，并且说出来**。选中订单时价格下拉**自动切到客户申请的档位**，
   旁边显示一句 `The customer asked for 90 days · 3600.`——如果运营侧要按别的档位报价，
   那是一个**看得见的决定**，不再是悄悄换掉。

**浏览器实测（两侧）**：

| 侧 | 动作 | 结果 |
|---|---|---|
| 企业 | `Orders & documents` 打开订单表单 | 出现 `#offline-undertaking-term`，五个档位与运营侧**逐字相同**（`1 day · 49` … `365 days · 13870`），默认 `month` |
| 企业 | 选 `90 days · 3600` → `Create draft order` | 201，出现 `offline-order-d916b5b4-…`（Draft），提示 "Draft order created…" |
| 管理 | `Offline commerce` → 打开该订单 | 价格下拉**已经是 `quarter`**，并显示 `The customer asked for 90 days · 3600.` |

（运营侧点报价仍然会被 §12.4 的就绪闸门 503 挡住，这一点没有变——档位统一解决的是
"客户能不能提出一个运营侧可报的档位"，不是"能不能报价"。）

测试：`commercial/offline` 2/2、`ui/offline_commerce` 13/13、`cmd/enterprise` 28/28、
`cmd/console` 63/63、`api` 136/136。

### 12.10 第 7 步（开通权限）走通了，走的是另一条不经过 offline commerce 的路

承诺函那条链第 7 步被就绪闸门挡住（§12.4），但"开通权限"本身在管理侧有一条**独立且可用**的路：
`Users & access` → `GUIDED SETUP / Create WebIDE access`。

**按下的东西与反馈**：

| # | 侧 | 按下/填写 | 结果 |
|---|---|---|---|
| 1 | 管理 | 填 `Display name` / `Work email` / `Organization` / `Tenant` / `Provider subject`，点 `Identity verified` | `Prepare access` 由灰变亮 |
| 2 | 管理 | `Prepare access` | **`POST /v1/onboarding/access-packages 201`**，提示 **"WebIDE access was prepared. The next incomplete milestone is shown below."** |
| 3 | 管理 | 观察包卡片 | 一次点击把**四个里程碑**做完：`✓ Identity complete` `✓ Organization complete` `✓ MasterLease complete` `✓ Workspace & models complete`，只剩 `· WebIDE next`；状态 `ReadyToEnable` |
| 4 | 管理 | `Enable WebIDE` | 提示 **"WebIDE access is enabled."**，状态 `ReadyToEnable → Ready`，五个里程碑全部 `✓` |

这一步的**反馈质量是本次走查里最好的一段**：一句"下一步未完成的里程碑在下面"直接把注意力指到该点的地方，
里程碑用 `✓ complete / · next` 区分，每次动作都有 notice。用户数/授权数也从 `22 users · 26 grants` 变成
`24 users · 28 grants`，计数跟着动。

**堵点 H（中等，但会挡住真实使用）：`Provider subject` 这个字段 —— 已在 §12.16 修掉并实测**

- 标签只有四个字 `Provider subject / 提供商主体`，**没有任何说明文字**（`ui/console.mbt:4642`），
  而且是 `type=password`，输入时看不见；
- 它要的是**身份提供商的原始 subject**（Keycloak 的用户 UUID）。而 LunaNexa 的任何界面都不显示这个值 ——
  `Users & access` 的用户表里显示的是 `subject-f1af5bc2d95ea4ad7e415d77` 这种**派生指纹**，
  企业侧 `Account & API keys` 显示的也是同一个指纹；
- 所以操作员要给一个"平台里已经存在的人"开通权限时，**必须去 Keycloak 自己的管理台把这个 UUID 抄出来**。

  **这一条不是加一句文案就能修的**，当时如实记下两种改法（都需要动结构）：

  1. 让 `identity_subject_digest` 在 js 目标可用。它现在在 `account` 包里，而
     `account` 是 `supported_targets = "native"`（里面有 Postgres / 文件存储），
     `ui` 是 `js+native`，所以**控制台算不出这个摘要**（实测报
     `Selected backend 'js' is incompatible … 'vectie/lunanexa/ui' requires 'vectie/lunanexa/account'`）。
     把它挪到一个 `js+native` 的小包，控制台就能**边输入边显示派生引用**，
     操作员可以拿它跟账户列表里的 `Subject` 核对之后再提交。 ← **最终走的就是这条**（§12.16）
  2. 更彻底：开通权限时**从账户列表里选人**，而不是让操作员重新输入原始 subject。
     这需要 API 接受 `subject_ref` —— 现在它只收 `identity_subject`，并自己算摘要校验
     （`api/access_onboarding_http.mbt:103`），所以这条要动接口。**没做**：它要改开通接口的入参语义，
     而第 1 条已经能把"抄错人"这件事变成可见的，收益足够。

本次走查当时用的是**合成 subject**（`9f8e7d6c-…`）：包能建、里程碑能推进、状态能变 `Ready`，
但**没有真人能用这个身份登录**，所以"企业侧得到权限"这一步**没法对它验证** ——
而这恰好说明了这个字段为什么必须填真值。（§12.16 的实测改用了真值。）

**第 8 步在企业侧的显示（已核对，是完整的）**：`Account & API keys` 页给出
`AUTHENTICATED ACCOUNT / Identity & membership`：Active membership、账号名、邮箱、`Account ID`、
`Account state: Active`、角色 `Enterprise user`、`Organization` / `Tenant` / `Subject`（都可复制）、
以及 `Browser sessions` 列表。也就是说"我到底有什么权限"在企业侧是看得清的。
承诺函链开通后的权限会长什么样，本轮无法验证（链没走到）。

### 12.11 用**真实身份**开通权限：管理侧记下了，企业侧看不出来

12.10 用的是合成 subject，所以第 8 步没法验证。这一节换成**真实身份**：把
`tier-1790051168@example.test` 在 Keycloak 里的真实 subject
（`db28abc9-ed6c-4478-8852-b325d97c8e4b`，就是 §12.10 堵点 H 里说的"得去 Keycloak 抄"的那个值）
填进 `Provider subject`，再走一遍：

| # | 侧 | 按下 | 结果 |
|---|---|---|---|
| 1 | 管理 | `Prepare access` | 201，包状态 `ReadyToEnable`，`✓ Identity` `✓ Organization` `✓ MasterLease` `✓ Workspace & models`，只剩 `· WebIDE next` |
| 2 | 管理 | `Enable WebIDE` | **"WebIDE access is enabled."**，状态 `Ready`，五个里程碑全 `✓` |

管理侧这一步是**扎实的**：真实身份、真实授权、每步都有反馈。

**但企业侧没有任何变化。** 拿一个**从未开通过**的账号做对照
（`chain-1790049130@example.test`，同样自助注册、同样有试用），两边的 `WebIDE` 页逐行对比：

```
diff 之后只剩三处不同，全部是账号自己的标识：
  subject-f1af5bc2… · trial-org-f1af5bc2…        ← 开通过的账号
  subject-13a398e9… · trial-org-13a398e9…        ← 从未开通的账号
```

其余**逐字相同**，包括：

```
SECURE WEBIDE HANDOFF
Continue your leased workspace in MoonDesk / MoonCode
Your access is ready. Open the selected WebIDE to continue.
[Open MoonDesk / MoonCode]
Your access journey
1 Signed in        Your identity and Developer membership are verified.
2 MasterLease      Contract is effective.
3 Workspace access Developer lease is active.
4 Approved models  17 个模型
5 Open WebIDE      One click opens MoonDesk / MoonCode with a 120-second single-use handoff.
Approved models: 17 · Previous connections: 0 · Access remains lease-bound
```

**结论：这一步两侧没有对上。** 管理侧确实记下了授权（平台自己的计数从
`22 users · 26 grants` 走到 `24 users · 28 grants`，里程碑也逐项推进），
但企业侧那块 `WebIDE` 页是由**企业侧自己的 membership / lease / 模型读取**渲染的，
而试用本来就已经给了 Developer 成员资格和 lease —— 所以"管理侧刚给你开了权限"这件事
**在客户界面上没有任何痕迹**。

还有一处值得记：**管理侧的"用户表"里也看不出这次授权**。把两个账号在
`Users & access` 的用户表里逐行对比，除了各自的标识之外**完全一样**
（同样的列、同样的 `Active`、同样三个角色复选框、同样的 `Suspend… / Revoke…`）——
授权只出现在 `GUIDED SETUP` 那一段的**包卡片**上（按显示名列出、带五个里程碑）。
也就是说"这个账户到底被开了什么"在两个地方都不好回答：用户表里没有，客户页面上也没有。

需要说清的是这**不等于**"开通无效"：本次能对照的两个账号都有试用，
**部署上没有"没有试用的账号"可做对照**，所以无法区分是
（a）授权包对客户视图确实没有影响，还是（b）有影响但被试用权益盖住了。

> **这个边界已经在 §12.17 解掉了。** 结论是 (a) 的加强版：**不是被盖住，是两套租户**。
> 管理侧开通时把这个人绑到了操作员手填的 `tenant-recon-h`，而客户会话解析的是
> 他自助注册时的 `trial-tenant-…`；管理侧 `Leases` 页能同时看到两条租约，企业侧只看得到一条。
> 所以第 8 步在 §12.0 里已经从"⚠️ 一半"改成 **⛔ 实际上没拿到**（堵点 J）。
要判死这一点，需要一个**不带试用**的账号做第三个对照。

### 12.12 要解锁第 3–6 步，具体需要做什么（可执行清单）

这不是代码问题，是**运维/法务/财务要真实证明的东西**。

**「十项能力」是代码里钉死的十项**，不是文里的约数：`commercial/offline/types.mbt:78` 的
`OfflineCommerceCapability` 枚举正好十个，`commercial/offline/readiness.mbt` 里
`capabilities.length() != expected.length()` 会直接报 `ReadinessCapabilitySetInvalid`，
而且**每一项必须恰好出现一次**（`ReadinessCapabilityDuplicate`），
每项还要 `configured && verified` 且带一个合法的 `evidence_ref`：

| # | 能力（枚举值） | 缺它时的 blocker code | 需要先真实具备的东西 |
|---|---|---|---|
| 1 | `ApprovedLegalTemplates` | `ApprovedLegalTemplatesPending` | 已批准的中英双语法律 DOCX 模板 + 不可变哈希 + 具名法务负责人 |
| 2 | `ObjectStorage` | `ObjectStoragePending` | S3 兼容对象存储：租户隔离前缀、保留策略、版本、加密、短时 multipart 上传授权 |
| 3 | `MalwareScanner` | `MalwareScannerPending` | 恶意/主动内容扫描，带签名回调与 ZIP 炸弹上限 |
| 4 | `OoxmlWorker` | `OoxmlWorkerPending` | 管理面文档 worker，固定镜像摘要 + 只读模板挂载 |
| 5 | `PdfRenderer` | `MoonLeafPdfRendererPending` | 确定性的 MoonLeaf DOCX→PDF 渲染 + **逐页图像视觉回归基线** |
| 6 | `SpreadsheetFormulaEngine` | `SpreadsheetFormulaEnginePending` | XLSX 公式重算、错误扫描、渲染页检查 |
| 7 | `CjkFonts` | `CjkFontsPending` | 随渲染器一起保留的中文生产字体证明 |
| 8 | `MachineCallbackIdentity` | `MachineCallbackIdentityPending` | 与人类运维权限**分离**的 mTLS 或签名回调身份（≥32 字节，互不相同） |
| 9 | `EntitlementAuthority` | `EntitlementAuthorityPending` | 第三套不可复用身份 `LUNANEXA_ENTITLEMENT_AUTHORITY_CALLBACK_TOKEN`：未确认前订单不算履约 |
| 10 | `FinanceLegalPolicy` | `FinanceLegalPolicyPending` | 已批准的履约政策：先票/后票、退款、作废、取消、到期、权限撤销 |

**上面十项之外，还有一组 blocker 不是"能力"，是"适配器/证据"**——签名文档写了十项也照样会报：

| blocker code | 需要先真实具备的东西 |
|---|---|
| `ReadinessTransferAdapterUnavailable` | 传输适配器三元组（endpoint / token / session secret ≥32 字节），endpoint 非 loopback 时必须 HTTPS |
| `ReadinessEvidenceExpired` / `ReadinessCapabilitySetInvalid` / `ReadinessCapabilityDuplicate` / `ReadinessEvidenceReferenceDuplicate` / `ReadinessEvaluationTimeInvalid` | 一份**签名**就绪文档：schema `lunanexa.offline-commerce-readiness.v1`、签发/失效窗口 ≤31 天、十项各恰好一条、`evidence_ref` 唯一且 ≤256 字符、用 HMAC-SHA256 签名 |
| `ReadinessArtifactDispatcherHeartbeatStale` / `…SuccessStale` | artifact dispatcher 真的在轮询受保护的工作路由，并留下近期心跳与成功回执 |
| `ReadinessEntitlementDispatcherHeartbeatStale` / `…SuccessStale` | entitlement dispatcher 同上 |

文档的原话是：**"Signed evidence or a deployment boolean alone cannot make these adapters
ready."** —— 所以这组不能靠文档糊过去，得有真在跑的东西。

然后把 `LUNANEXA_OFFLINE_COMMERCE_READINESS_PATH` 与 `…_SECRET` 挂到控制面容器上
（**当前全集群没有任何 Pod 挂这两个变量**，Secret 内容就是字面量 `pending`）。

另外文档还要求两项**演练**才算完：`offline_commerce` 快照与不可变审计链的备份/恢复，
以及一次**跨角色 UI-to-UI 演练**（法务、财务、采购方、复核人、运维）+ 一次线下实物履约演练。

在这之前，文档的原话是：**"the platform may demonstrate state transitions locally but must not
represent the generated packet or uploaded evidence as legally executed or financially settled."**
—— 也就是说，本报告没有把任何东西说成"已合法签署/已结算"，第 3–6 步保持"不可达"是**正确的状态**。

### 12.13 堵点 I 已修：冻结报价的确认框现在说出金额

原文案（点 `Quote undertaking tariff` 之后弹出的确认框）：

```
CONSEQUENTIAL ACTION
Freeze this immutable quote?
…
offline-order-d916b5b4-… · quarter × 1          ← 只有档位和台数，没有价格
[Go back]  [Confirm with this evidence]
```

这是个**价格动作**，而屏幕上从来没出现过价格。现在改成（浏览器实测）：

```
offline-order-d916b5b4-… · quarter × 1 · CNY 3600
```

金额用**同一份共享档位表**（§12.9 的 `undertaking_term_tiers`）乘以屏幕上填的台数算出来，
不另外写死数字；台数不是数字时**不显示金额**，而不是显示一个没人填过的总额。
顺带确认共享档位仍然生效：这个订单是客户按 `quarter` 申请的，运营侧打开时下拉就在 `quarter`。

测试：`ui/offline_commerce` 14/14、`cmd/console` 63/63、`cmd/enterprise` 28/28。

### 12.14 堵点 F 已修：根因是门户的传输层把 HTTP 状态码丢掉了

**根因**（不是 `friendly_failure` 的问题，也不是控制面的问题）：

`cmd/enterprise/main.mbt` 的 `request_promise` 原来这样抛错：

```js
if (!response.ok) {
  let message = `HTTP ${response.status}`;
  try { message = JSON.parse(text)?.error?.message || message; } catch (_) {}
  throw new Error(message);        // ← 有 error.message 时，状态码被整条替换掉
}
```

只要响应体带 `error.message`，抛出的字符串就**只剩那句话**，`HTTP 403` 没了。
于是 `friendly_failure` 按 `raw.contains("403")` 分类时**永远匹配不上**，落到兜底分支
"操作失败，请刷新后重试" —— 而这恰恰是一个**重试永远不会成功**的权限拒绝。

**怎么证明是这里而不是分类函数**：把同一个按钮的请求用 CDP `Network.setBlockedURLs` 掐断，
提示变成 **"The connection did not complete. Check your network and refresh status before retrying"**
—— 说明分类函数工作正常（`fetch` 那条分支命中了），丢的是**抛出字符串里的状态码**。

**修法**：状态码保留在消息里，上游原文也保留。

```js
let detail = "";
try { detail = JSON.parse(text)?.error?.message || ""; } catch (_) {}
throw new Error(detail ? `HTTP ${response.status}: ${detail}` : `HTTP ${response.status}`);
```

**浏览器实测（同一个按钮，同一个 403 `MachineOrderAccessDenied`）**：

| | 提示 |
|---|---|
| 改之前 | `Operation: The action failed. Refresh and retry; if it persists, contact your operator with the action and time. Sensitive technical details are hidden.` |
| 改之后 | **`Operation: This account lacks permission for this action. Check the selected organization and ask its administrator.`** |

顺带核对了另外两个前端：**控制台早就是对的**（`HTTP ${response.status}: ${detail}`），
所以这个缺陷只在企业门户这一侧。测试：`ui/enterprise` 37/37、`cmd/enterprise` 28/28。

### 12.15 堵点 G 已修：租期超出规格上限时明说是哪一条越界

`Rental period` 选 `7 days`（168 小时）或 `30 days` 时，`Review price` 会直接变灰，
而页面上唯一的解释是下拉下方那句**静态**小字 `0–24 hours allowed` —— 它既没说这是
**试用/规格**的限制，也没说该怎么办。对试用租户来说，"选长租期"的全部可见后果就是按钮灰掉。

现在同一个位置会多出一行明确的错误（浏览器实测，选 `7 days` 之后）：

```
168 hours is longer than this offering allows. Pick a shorter period, or ask an operator for a longer order.
```

同时 `Review price` 仍然是 disabled（规则没变，只是不再沉默）。数字由 `duration_hours`
与 `offering.maximum_duration_hours` 现场算出，不在文案里写死。

测试：`ui/enterprise` 38/38、`cmd/enterprise` 28/28、`cmd/console` 63/63。
### 12.16 堵点 H 已修：`Provider subject` 现在当场显示它会派生成谁

**问题的实质不是"缺一句说明"，是"抄错了没人知道"。**
`Provider subject` 收的是身份提供商的原始 subject（Keycloak 的用户 UUID），
而 LunaNexa 所有界面显示的都是**派生指纹**（`subject-…`）。
两者之间没有任何可见的联系，所以：

- 操作员必须去 Keycloak 管理台抄 UUID；
- 抄错（抄了另一个人的、或者粘贴时多带一个空格）时，平台**照样建出一个账户**，
  只是建到了别人的 `account-<指纹>` 上 —— 界面上没有任何一处会因此显得不对。

**改法（走的是 §12.10 里记的第 1 条）**

1. 新增 `account/identity` 包（`supported_targets = "js+native"`，只依赖
   `moonbitlang/x/crypto` + `moonbitlang/core/encoding/utf8`），
   把**规范材料**和派生放进同一处：

   ```
   subject_material(issuer, subject) = "lunanexa.external-identity.v1\n{issuer}\n{subject}"
   subject_digest     → "sha256:<64 hex>"        （存进 identity_subject_sha256 的那个值）
   subject_fingerprint→ 前 24 个 hex             （所有 subject-… / account-… 的后缀）
   subject_reference  → "subject-<fingerprint>"
   account_identifier → "account-<fingerprint>"
   ```

2. 原来的三处各自切片，现在**全部委托到这一处**，所以"外部身份哈希成什么"只有一
   个定义：

   | 位置 | 改之前 | 改之后 |
   |---|---|---|
   | `account/store.mbt:24` `identity_subject_digest` | 自己拼材料、自己哈希 | 委托 `@identity.subject_digest`（公开 API 不变） |
   | `account/store.mbt:745` `register_with_invitation` | `external_digest[7:31]` | 委托 `@identity.subject_fingerprint` |
   | `account/store.mbt:870` `register_open` | `external_digest[7:31]` | 同上 |
   | `api/access_onboarding_http.mbt:34` `webide_access_package_fingerprint` | `digest[7:31]` | 同上 |

3. `ui` 加依赖 `vectie/lunanexa/account/identity`（**不再需要** `ui → account`，
   所以 `account` 保持 native-only 不用动），在**两个**填 subject 的地方渲染派生结果：

   - `Users & access → Create WebIDE access → Identity provider details`（`#access-provider-subject`）
   - `Users & access → Advanced: create account only`（`#account-provider-subject`）

   空值时给说明，有值时给结果：

   | 状态 | 页面上实际出现的那一行 |
   |---|---|
   | 空 | `Paste the provider's own subject (the id the provider issued), not the derived reference. LunaNexa derives the account reference below; nothing leaves the browser until you submit.` |
   | 填了真值 | `Derives subject-fe3ed0627ed85ce6e51cf621 · account-fe3ed0627ed85ce6e51cf621 — check it against the Subject column below before you submit.` |

   `aria-describedby` 也补上了，两个输入框以前连提示都没有。

4. **哈希取的是"提交时的原文"，不做 trim。** 这一条是刻意的：
   如果在这里顺手 trim，粘贴时多带的空格会被**悄悄修掉**，页面显示"对得上"，
   而控制面存下去的是另一个身份 —— 正是这个预览要防的事。
   所以多一个空格会显示成**对不上的指纹**，操作员当场就能看出来。
   （`ui/console_identity_wbtest.mbt` 里专门有一条测试钉住这个行为。）

**顺带修掉的一处错文案**：账户表单原来的提示是
`Submitted once for hashing; neither the provider subject nor its digest appears in account views.`
—— 对完整摘要成立，但对**平台到处都显示的那个派生引用**完全不成立，
等于把操作员往"不用核对"的方向推。现在两个表单共用同一段预览文案。

**真实集群实测（2026-09-22，浏览器，非命令行）**

用真值走了一遍操作员的实际动作：从 Keycloak 管理台取 `wlc` 的 subject
（`30101bc7-bac5-4b1e-b747-8239044367f8`，与账户记录里的 issuer
`https://106.39.18.146:5006/realms/lunanexa` 配对）。

| | 值 |
|---|---|
| 账户列表里 `Platform Operator / wlc@lunanexa.local` 的 `Subject` 列 | `subject-fe3ed0627ed85ce6e51cf621` |
| 把上面那个原始 subject 填进 `Provider subject` 后，页面当场显示 | **`Derives subject-fe3ed0627ed85ce6e51cf621 · account-fe3ed0627ed85ce6e51cf621`** |
| 两者是否一致 | **一致** |
| 清空输入框 | 变回上面那段说明文案 |

`Advanced: create account only` 面板同样填真值，同样得到
`Derives subject-fe3ed0627ed85ce6e51cf621 · …`，且旧文案
（`neither the provider subject nor its digest appears in account views`）在页面上已不存在。

**这一步的意义**：操作员现在**不需要离开产品**就能确认"我抄的这个 UUID 就是列表里那个人"。
派生的正确性也不靠人眼——`account/identity` 里有一条**golden 哈希**测试钉住规范材料，
`ui` 里有一条测试断言预览值等于 `@identity.subject_reference(...)`，
即控制台显示的值和账户存储落下去的值是同一个函数算出来的。

**没做的部分（如实）**

- 没有改成"从账户列表里选人"（§12.10 的第 2 条）。它要改开通接口的入参语义，
  而第 1 条已经把"抄错人"从静默变成可见，收益足够，风险小得多。
- 第 3–6 步依然被 offline commerce 的生产闸门挡着（§12.4），与本节无关。
  所以**没有**借着这次改动把任何东西说成"已签署/已结算"。

**测试与部署**

| 目标 | 结果 |
|---|---|
| `account/identity`（js / native） | 4/4 · 4/4 |
| `ui`（js） | 86/86（含 4 条新增的预览测试） |
| `ui` + `account` + `api`（native） | 237/237 |
| `ui/enterprise` + `ui/offline_commerce` + `cmd/console` + `cmd/enterprise`（js） | 143/143 |

镜像：`lunanexa-web:20260922-r7`
（registry digest `sha256:904a82a690b7c38fdb57ed9f6f58fc34c33ea9996b6102d74eca5fb13d46c128`），
`lunanexa-console` 已 rollout；门户目录同步后 `enterprise.js` 摘要未变
（`801fc44116c9a8a68646f127f4310ea946ade6d2aa0c18803b42767893db4b8a`，本次没动企业侧源码）。
浏览器侧做了硬刷新（`Network.setCacheDisabled` + `Page.reload ignoreCache`）后再测，
确认跑的不是旧 bundle。
### 12.17 第 7→8 步用**真实身份**走通管理侧，企业侧却毫无变化：堵点 J

§12.10 用合成 subject 走通了第 7 步，但第 8 步只能打"⚠️ 一半"，因为**合成身份没法登录企业侧**。
这一节换成一个**真人**：通过企业门户 UI 自助注册一个新账号，拿到它在 Keycloak 里的真 subject，
再回到管理侧把这个人开通。两侧都看得到，所以第 8 步能真正判定了。

**结论：管理侧显示"全部完成"，企业侧一点变化都没有。开通落到了一个客户会话解析不到的租户上。**

#### 走的过程（全部在浏览器里按，没有用命令行驱动）

| # | 侧 | 按下的东西 / 填的值 | 结果 |
|---|---|---|---|
| 1 | 企业 | `Log out` → `Register a new account` → 邮箱 `recon-h-1790053838@example.test` / 名称 `Recon H Enterprise` / 密码 → `Create account` | ✅ 门户渲染，`Account & API keys` 显示 `account-a409fbcfca89d44f3b16bdf1` / `subject-a409fbcfca89d44f3b16bdf1` |
| 2 | （诊断读） | 从 Keycloak 管理 API 取这个人的原始 subject | `97716b94-fc9e-4cc3-9f0e-3d613537b07c` |
| 3 | （本地核对） | 用同一份规范材料算指纹 | `a409fbcfca89d44f3b16bdf1` —— 与第 1 步门户自己算出来的**完全一致** |
| 4 | 管理 | `Users & access` → `Create WebIDE access` 填 `Display name` / `Work email` / `Organization=organization-recon-h` / `Tenant=tenant-recon-h`，展开 `Identity provider details` 填 issuer + 上面那个真 subject | 预览显示 **`Derives subject-a409fbcfca89d44f3b16bdf1 · account-a409fbcfca89d44f3b16bdf1`**（§12.16 的修复在这里第一次用于真值） |
| 5 | 管理 | `Identity verified` → `Prepare access` | ✅ notice：`WebIDE access was prepared. The next incomplete milestone is shown below.`；卡片 `ReadyToEnable`，四个 `✓` + `· WebIDE next` |
| 6 | 管理 | 该卡片上的 `Enable WebIDE` | ✅ `POST /v1/onboarding/access-packages/account-a409fbcfca89d44f3b16bdf1:enable → 200`；卡片 `ReadyToEnable → Ready`，五个 `✓`，`Ready for WebIDE` |
| 7 | 企业 | 硬刷新门户 → `Account & API keys` | ❌ **与第 1 步逐字相同**：`Organization = trial-org-a409fbcfca89d44f3b16bdf1`、`Tenant = trial-tenant-a409fbcfca89d44f3b16bdf1`、角色仍只有 `Enterprise user` |
| 8 | 企业 | `WebIDE` 页 | `Your access is ready. Open the selected WebIDE to continue.` —— 但**这句在第 6 步之前就已经是这样**，是试用给的，不是这次开通给的 |

管理侧那张卡片的完整文本（第 6 步之后）：

```
Recon H Enterprise  recon-h-1790053838@example.test
organization-recon-h · tenant-recon-h  Ready
✓ Identity complete  ✓ Organization complete  ✓ MasterLease complete
✓ Workspace & models complete  ✓ WebIDE complete  Ready for WebIDE
```

#### 决定性证据：同一个人的**两个**租户，管理侧都看得见，企业侧只看得到其中一个

管理侧 `Leases` 页，同一个 subject `trial-user-a409fbcfca89d44f3b16bdf1` 名下**两条** Active 租约：

| 租约 | 租户 | 规格 | 来源 |
|---|---|---|---|
| `lease-a409fbcfca89d44f3b16bdf1` | **`tenant-recon-h`** | Text generation · 2 concurrent | 本次开通（第 5/6 步） |
| `trial-lease-a409fbcfca89d44f3b16bdf1` | **`trial-tenant-a409fbcfca89d44f3b16bdf1`** | Text generation · 1 concurrent | 自助注册送的试用 |

企业侧 `Account & API keys` 只显示 `trial-tenant-a409fbcfca89d44f3b16bdf1`。

#### 代码上为什么必然如此

> **这一小节后来往下挖了一层，机制比这里写的更具体：见 §12.19。**
> 这里说的"客户的会员租户"是对的，但**为什么**解析到试用那一个，当时的解释还不完整。

企业侧"WebIDE 是否就绪"读的是**门户会员（portal membership）的租户**，不是开通包的租户：

```moonbit
// api/client_handoff_http.mbt:257  —— GET /v1/portal/self/clients
let workspace_ready = match self.workspace_directory {
  Some(directory) =>
    try {
      ignore(
        directory.authorize_subject_for_tenant(
          subject_ref,
          portal_view.membership.tenant_ref,   // ← 客户的会员租户
          Developer,
          now,
        ),
      )
      true
    } catch { _ => false }
  None => false
}
```

而开通包建的是一套**另一个租户**的会员和租约，租户名来自操作员在表单里手打的
`#access-tenant`（`api/access_onboarding_http.mbt` 的 `WebIDEAccessPackageIntent.tenant_ref`
只做 `@contracts.valid_identifier` 格式校验，**不校验它跟这个人的既有会员是否一致**）。

自助注册那边用的是另一套名字（`api/account_http.mbt:305`）：

```moonbit
organization_id: "trial-org-\{fingerprint}",
tenant_ref:      "trial-tenant-\{fingerprint}",
```

于是同一个人的名下出现两个租户，而客户的会话永远解析到试用那一个。

#### 为什么这是一个**堵点**而不是"操作员填错了"

- `Organization` / `Tenant` 是**自由文本输入框**，页面上**没有任何地方**告诉操作员
  这个人现在在哪个租户上——平台明明知道（账户列表里就有），只是没显示；
- 填错**不会报错**：`200`、五个 `✓`、`Ready for WebIDE`。管理侧的反馈是"成功了"；
- 企业侧的反馈是"什么都没发生"，而且**没有任何一处**把这两件事联系起来；
- 所以第 8 步不是"没验证"，是**照现在这样做就是做不到** —— 除非操作员事先从别处问到客户的租户名，
  而这正是堵点 H 的同一类问题：**手填身份字段 + 平台不给出可核对的既有值**。

#### 两种改法（都**没有**实施，需要你定）

1. **把既有值显示出来**（与 §12.16 同构、改动小、不改策略）：操作员填完 issuer + subject 后，
   控制台按派生出的 `account-<指纹>` 在账户列表里查这一行，把这个人的
   `Display name / Email / Organization / Tenant` 显示在 `Organization` / `Tenant` 输入框下面，
   让操作员**照着填**而不是**猜着填**。填不一致时仍然是允许的（有些场景确实要开新租户），
   但至少不一致是**看得见**的。
2. **不让手填**：`Organization` / `Tenant` 改成从该 subject 的既有会员里**选**，
   只有显式勾"为新租户开通"才允许输入新值。这要动开通接口的入参语义和一条新的校验
   （"开通包的租户必须等于或显式新建于该 subject 的既有会员"），是设计决策。

我倾向第 1 种（先让不一致可见），但**没有替你选**——因为"允不允许给同一个人开第二个租户"
是产品策略，不是 bug。

#### 本次实测做了什么、没做什么（如实）

- 用的是**真身份**（Keycloak 里真存在、真能登录企业门户的账号），不是合成 subject。
  所以 §12.11 里"合成身份没法验证第 8 步"的那个缺口已经补上了。
- 顺带把 §12.11 的**边界**也解掉了：当时怀疑"是不是被试用权益盖住了"，现在可以确定
  **不是盖住，是两套租户**——证据是管理侧能看到两条租约、企业侧只看得到其中一条。
- **没有**清理这次开通留下的记录（`access-account-a409fbcfca89d44f3b16bdf1` 这个包、
  以及 `tenant-recon-h` 上那条租约）。留着是**故意的**：它就是本节的证据，
  而且删掉它反而会让"管理侧显示成功、企业侧没反应"这件事变成不可复现。
  要清理的话：管理侧 `Users & access` 里对该包做 revoke，再在 `Leases` 页释放那条租约。
- **没有**修 J（见上面的两种改法）。所以第 8 步在报告里记的是 **⛔ 实际上没拿到**，
  不是"通了"，也不是"没验证"。
### 12.18 堵点 J：把"租户填得不一样"从静默变成可见（已实测）

§12.17 里两种改法，选的是**第 1 种**：不禁止，只显示。理由写在 §12.17——
"允不允许给同一个人开第二个租户"是产品策略；而且禁止手填会让"确实要开新租户"的场景无路可走。
所以这次只做**信息**：把平台已经知道的、这个 subject 名下的租户列出来，让操作员**照着填**而不是**猜着填**。

**改了三个地方**

1. `ui/console.mbt` 的 `ComputeLeaseRow` 增加 `subject_ref`。
   这个字段本来就在控制台已经拉取的 workspace 快照里（`WorkspaceLease.subject_ref`），
   只是构造行的时候被丢掉了（`cmd/console/main.mbt`），所以**不需要新接口、不需要新请求**。

2. 新增 `access_existing_authority(...)`，渲染在 `Organization` / `Tenant` 两个输入框下面，
   并给 `#access-tenant` 补上 `aria-describedby`。三种状态：

   | 状态 | 页面上实际出现的那一行 |
   |---|---|
   | 身份详情还没填 | `Fill in Identity provider details first; LunaNexa then lists the tenants this subject already holds, so you can reuse the customer's own tenant instead of inventing one.` |
   | 这个 subject 平台里没有 | `LunaNexa holds no account or workspace lease for this subject yet. The organization and tenant below are the ones the package will create.` |
   | 这个 subject 已经存在 | `This subject already exists: <姓名> · <邮箱> · <subject 引用>. Tenants it already holds: <租户列表>. The customer's own sign-in resolves its tenant from its existing membership, so a package opened on a different tenant will not be visible to them.` |

3. 同一 subject 的多条租约**去重**，别人的租约不会被算进来（有测试钉住）。

**真实集群实测（2026-09-22，浏览器，非命令行）**

拿 §12.17 那个真账号（`recon-h-1790053838@example.test`，subject
`97716b94-fc9e-4cc3-9f0e-3d613537b07c`）复测，页面当场显示：

```
This subject already exists: Recon H Enterprise · recon-h-1790053838@example.test
· subject-a409fbcfca89d44f3b16bdf1. Tenants it already holds:
tenant-recon-h, trial-tenant-a409fbcfca89d44f3b16bdf1.
The customer's own sign-in resolves its tenant from its existing membership,
so a package opened on a different tenant will not be visible to them.
```

**两个租户都在列表里**——包括客户自己会解析到的那一个（`trial-tenant-a409fbcfca89d44f3b16bdf1`）。
也就是说 §12.17 里那个"管理侧显示成功、企业侧没反应"的坑，现在**在按下 `Prepare access` 之前**
就摆在操作员眼前了。同一页面上，`Provider subject` 下面是 §12.16 的派生引用，
`Tenant` 下面是这里的既有租户——两个手填的身份字段都有了可核对的锚点。

也复测了另外两种状态：清空身份详情 → 回到"先填身份详情"那句；填一个平台里不存在的
subject → `LunaNexa holds no account or workspace lease for this subject yet.`

**没做的部分（如实）**

- **没有**禁止给同一个人开第二个租户，也**没有**改成从既有租户里选。那是策略决定（§12.17 的第 2 种改法）。
- **没有**让企业侧显示"管理侧给你开了什么"。§12.17 记的那个"企业侧毫无变化"依然成立——
  这次只是让操作员**在开之前**知道会这样，没有改变"开在别的租户上客户就看不到"这个事实。
- §12.17 里那次开通留下的包和租约仍然没清理，它们是证据。

**测试与部署**

| 目标 | 结果 |
|---|---|
| `ui`（js） | 89/89（3 条新增：既有租户列出并去重、未知 subject、未填 subject） |
| `ui/enterprise` + `ui/offline_commerce` + `cmd/console` + `cmd/enterprise`（js） | 143/143 |
| `ui` + `account` + `account/identity` + `api`（native） | 240/240 |

镜像：`lunanexa-web:20260922-r8`
（registry digest `sha256:e160b51963a39f7e66ac029acb51b6c2d370fd62a44b740d5241e1908cbe27c4`），
`lunanexa-console` 已 rollout；浏览器硬刷新后再测。
### 12.19 堵点 J 的根因再往下一层：开通包建的"组织"在商业平面里不存在

§12.17 说"客户的会话解析到试用那个租户"，但没回答**为什么**它不解析到开通包那个。
再挖一层之后，机制是这样的——而且这一层比 §12.17 写的那一层更接近**缺陷**。

#### 机制（四步，每一步都有实测或代码）

1. **开通包只建了"门户会员"，没建"商业组织"。**
   实测（管理侧 operator 快照）：这个 subject 名下**两条 active 会员**，
   一条是开通包建的、一条是自助注册送的：

   | membership_id | organization_id | tenant_ref |
   |---|---|---|
   | `membership-a409fbcfca89d44f3b16bdf1` | **`organization-recon-h`** | **`tenant-recon-h`** |
   | `trial-membership-a409fbcfca89d44f3b16bdf1` | `trial-org-a409fbcfca89d44f3b16bdf1` | `trial-tenant-a409fbcfca89d44f3b16bdf1` |

   但商业平面里**只有试用那个组织**：

   | 请求 | 结果 |
   |---|---|
   | `GET /v1/commercial/organizations/trial-org-a409fbcfca89d44f3b16bdf1/snapshot` | **200**（组织在里面） |
   | `GET /v1/commercial/organizations/organization-recon-h/snapshot` | **409 `CommercialRejected` · commercial snapshot is unavailable** |

2. **客户端的"组织列表"只列商业平面里有的组织**，所以开通包那个被丢掉了：

   ```moonbit
   // api/self_service_organization_http.mbt:225  —— GET /v1/portal/self/organizations
   for membership in memberships {
     match commercial.organizations.iter().find_first(
       organization => organization.organization_id == membership.organization_id,
     ) {
       Some(organization) => organizations.push(...)   // ← 商业平面里没有就跳过
       None => ()
     }
   }
   ```

3. **客户手里只剩一个组织，于是被"钉住"。**
   企业客户端把选中的组织写进 `localStorage["lunanexa.organization"]`
   （`cmd/enterprise/main.mbt:445/454`），之后**每个**门户请求都带
   `X-LunaNexa-Organization`。实测（浏览器，硬刷新后抓到的请求头）：

   ```
   GET /v1/portal/self/organizations   org=trial-org-a409fbcfca89d44f3b16bdf1
   GET /v1/portal/self                 org=trial-org-a409fbcfca89d44f3b16bdf1
   GET /v1/portal/self/api-keys        org=trial-org-a409fbcfca89d44f3b16bdf1
   GET /v1/portal/self/clients         org=trial-org-a409fbcfca89d44f3b16bdf1
   …（每一个都带同一个值）
   ```

   而且**没有切换入口**：顶栏那个组织下拉（`ui/enterprise/enterprise.mbt:1516`）
   只在 `state.organizations.length() > 1` 时才渲染。实测页面上只有
   `select#enterprise-locale`，**没有** `select#enterprise-organization` ——
   也就是说客户**连手动切过去都做不到**，因为他只看得见一个组织。

4. **于是 `portal_view.membership` 永远是试用那条**，
   `workspace_ready` 就永远按 `trial-tenant-…` 算（§12.17 引的那段代码）。

顺带说明一句：`FilePortalStore::self_view`（`portal/store/file.mbt:268`）在
"一个 subject 有多条 active 会员且客户端**没有**指定组织"时是**失败关闭**的
（`OrganizationSelectionRequired`）。这个设计本身是对的。真正的问题是第 1、2 步——
**开通包能建出一条客户永远列不出来的会员**，所以"多组织"这条正确的保护路径根本没被触发。

#### 这为什么更像缺陷而不是策略

- 开通包自己的卡片写的是"一次点击把账户、会员、工作区档案、Developer 授权、
  申请的算力租约**作为一个包**准备出来"。商业组织不在这个包里，而**没有它，
  这个包在客户端就是不可见的**——客户既看不到，也切不过去。
- 这不是"操作员填错了租户名"：就算他填的是**这个客户已经有的**组织名，
  也会因为同样的原因（第 1 步没建商业组织）而…… 不，这一句要小心：
  如果操作员填的是 `trial-org-a409fbcfca89d44f3b16bdf1`，
  那个组织在商业平面里**是存在的**，第 2 步就不会丢，客户端也就会解析到它。
  **所以 §12.18 那个"把既有租户列出来"的提示，恰好也是这个坑的绕行办法**：
  照抄客户已有的组织名，包就会落在客户看得见的地方。

#### 三种改法（都**没有**实施）

1. **开通包补建商业组织**：在 `api/access_onboarding_http.mbt` 建会员时，
   如果 `organization_id` 在商业平面里不存在，就一并建出来。
   最彻底，但要定"用什么 display name / 法定主体 / 状态建"——自助注册那条路是要求
   提交法定主体资料的（`create_self_service_organization`），开通包这条没有。
   **这是产品决定。**
2. **客户端组织列表也列出"只有会员、没有商业组织"的组织**，
   让它至少能被选中。改动小，但会露出一个"半存在"的组织，语义上要解释清楚。
3. **只做提示**（已做，§12.18）：把既有租户列出来，让操作员照抄。
   不修根因，但把"静默失败"变成"按之前就看得见"。

我做了 3，**没做 1 和 2**。1 需要你定组织怎么建，2 需要你定"半存在的组织"该不该露出来。

#### 这次是怎么查到的（可复现）

| 步骤 | 做法 |
|---|---|
| 看客户端到底发了什么 | CDP `Network.requestWillBeSent` 抓 `/v1/portal/*` 的请求头 |
| 看组织列表有几条 | 检查 `select#enterprise-organization` 是否存在（只在 >1 时渲染）→ 不存在 |
| 看会员有几条 | 管理侧 operator 快照 `/v1/portal/operator/snapshot` 过滤这个 subject → 2 条 active |
| 看商业组织在不在 | `/v1/commercial/organizations/<id>/snapshot` → 试用 200，开通包那个 409 |
| 定位代码 | `api/self_service_organization_http.mbt:225`、`portal/store/file.mbt:268`、`cmd/enterprise/main.mbt:445`、`ui/enterprise/enterprise.mbt:1516` |
### 12.20 十项能力的逐项现状：哪些已装、哪些是工程活、哪些要你签字

§12.12 的清单回答了"要什么"，没回答"现在到哪了"。这一节把每一项对着**真实集群**核一遍。
判据分两层，先说清楚这两层的区别，否则容易误判：

- **十项能力本身，只有一个来源：那份签名就绪文档。**
  `cmd/control/main.mbt:274` 的 `load_offline_readiness_evidence` 把文档里的 `capabilities`
  原样交给 `offline_commerce_readiness`，`configured`/`verified`/`evidence_ref` 都是**文档里声明的**。
  所以"装了"不等于"算数"——还得有人声明它，且声明要在有效窗口内。
- **适配器那一组（三个回调身份、传输适配器、两个 dispatcher）走的是真实配置与心跳**，
  文档写什么都不算数。文档原话：*"Signed evidence or a deployment boolean alone cannot make
  these adapters ready."*

集群实测（`GET /v1/offline-commerce/operator/readiness`）：`status: OfflineCommerceAdaptersPending`，
`capabilities: []`，**17 条 blocker**。

#### A. 已经装好的（实测：对应的 blocker 不在那 17 条里）

| 项 | 证据 |
|---|---|
| 三个回调身份 token | `lunanexa-control-credentials` 里有 `artifact-worker-callback-token`、`artifact-scanner-callback-token`、`entitlement-authority-callback-token`，各 64 字节、互不相同。对应的 `ReadinessArtifactWorkerCallbackUnavailable` / `…Scanner…` / `…EntitlementAuthority…` **都没有出现** |
| 就绪文档的挂载点 | volume `offline-readiness` → `/etc/lunanexa/offline-readiness` 已经挂在 control 容器上 |
| 订单状态存储 | `LUNANEXA_OFFLINE_COMMERCE_PATH=/var/lib/lunanexa/offline-commerce.json`，`state` volume 挂在 `/var/lib/lunanexa` |

也就是说 `MachineCallbackIdentity` 和 `EntitlementAuthority` 的**配置那一半是完成的**；
没完成的是它们在文档里的**声明那一半**。

#### B. 没装，但是纯工程/配置（不需要你签字，需要有东西）

| # | 缺什么 | 实测现状 |
|---|---|---|
| 1 | `LUNANEXA_OFFLINE_COMMERCE_READINESS_PATH` + `…_SECRET` | **环境变量根本没挂**（只有 machine-readiness 那两个）。挂载点建了，Secret `lunanexa-offline-commerce-readiness` 里只有一个 key `pending`，内容就是字面量 `pending`。**这是十项声明的载体，不挂它，十项永远报 Pending** |
| 2 | 传输适配器三元组 | Secret 里**没有** `offline-transfer-adapter-endpoint` / `…-token` / `offline-transfer-session-secret` 这三个 key（env 里是 `optional: True`）→ `ReadinessTransferAdapterUnavailable` |
| 3 | artifact dispatcher | 全集群**没有任何**相关 Pod → `ReadinessArtifactDispatcherHeartbeatStale` + `…SuccessStale` |
| 4 | entitlement dispatcher | 同上 → `ReadinessEntitlementDispatcherHeartbeatStale` + `…SuccessStale` |
| 5 | 扫描器 / OOXML worker / XLSX 引擎 | 只有 Job 模板 `deploy/offline-artifact-worker-job.yaml`、`deploy/offline-pdf-pipeline-job.yaml`，镜像还是 `registry.invalid/lunanexa/control@${CONTROLLER_IMAGE_DIGEST}` 占位符 |
| 6 | 对象存储 | 没有任何 S3 兼容存储配置 |
| 7 | 一份签名就绪文档 | 仓库里**没有**示例文档，也**没有**生成/签名的脚本。`scripts/offline-commerce-manifest-test.sh` 是测试，不是生成器 |

#### C. 必须由外部提供的（这里做不出来）

| 项 | 为什么做不出来 |
|---|---|
| `CjkFonts` | `assets/fonts/private/README.md` 写明：字体二进制**故意不入库**，要从组织授权来源放进这个目录；脚本会校验内部 family 名与嵌入标志，**不允许用替代字体改名充数**。三个必需 face：`FangSong_GB2312.ttf`（仿宋_GB2312）、`FZXiaoBiaoSong-B05S.ttf`（方正小标宋简体）、`SimHei.ttf`（黑体）。当前目录里只有 `README.md` |
| `PdfRenderer` | MoonLeaf 侧还没有合格的渲染器镜像。`deploy/offline-pdf-pipeline-job.yaml` 的注释原话：*"Keep PdfRenderer and CjkFonts pending until `MOONLEAF_RENDERER_IMAGE_DIGEST`, bilingual fonts, visual baselines, and retained MoonLeaf receipts have been approved and rehearsed. Another office engine is not an allowed substitute."* |
| `ApprovedLegalTemplates` | 需要**具名法务负责人**批准中英双语模板 |
| `FinanceLegalPolicy` | 需要批准的履约政策（先票/后票、退款、作废、取消、到期、权限撤销） |

#### D. 需要**你**拍板的（这是"签字"的真实含义）

先澄清一件事，免得找错东西：那份就绪文档的 `signature` 是 **HMAC-SHA256**，
用 `LUNANEXA_OFFLINE_COMMERCE_READINESS_SECRET` 算出来的
（`cmd/control/main.mbt:240` `offline_readiness_signature`）。
**是机器签名，不是手写签名。** 所以没有任何一份文件需要你签名盖章。

真正需要你的是**四项批准 + 一项背书**：

| # | 需要你做什么 | 具体到哪一步 |
|---|---|---|
| 1 | **指定具名法务负责人并批准法律模板** | `ApprovedLegalTemplates` 的 `evidence_ref` 要指向这个批准 |
| 2 | **批准履约政策** | `FinanceLegalPolicy`：先票/后票、退款、作废、取消、到期、权限撤销各自的规则 |
| 3 | **接受 PDF 渲染的视觉基线** | `PdfRenderer` 要求"逐页图像视觉回归基线"，且是**真实法律模板**的基线——得有一个人认可渲染结果是对的 |
| 4 | **定对象存储的保留期** | `ObjectStorage` 的安装是工程活，但"存多久、谁能读"是合规决定 |
| 5 | **对整份文档背书** | 文档里十项各写 `configured: true` / `verified: true` + 唯一 `evidence_ref`，这是**责任声明**：写下去就等于说"这十项是真的" |

第 1–4 项是**内容**批准，第 5 项是**形式**背书。除这五项之外，其余全是工程活（B 组）。

#### E. 顺序建议（先做能做的）

1. 先做 B 组里 1–4 项（挂 readiness 环境变量 + 传输适配器 + 两个 dispatcher），
   这些不依赖任何批准，做完 `ReadinessTransferAdapterUnavailable` 和四条心跳 blocker 就会消失；
2. 同时推进 C 组的字体与 MoonLeaf 渲染器镜像（这两条是硬阻塞，谁批准都绕不过）；
3. 等你把 D 组 1–4 项的批准拿到，再生成并签那份文档（第 5 项），挂上去。
   文档一旦生效，`capabilities` 就不再是 `[]`，十项 Pending 会一起消失。

**注意**：第 1 步做完**不会**让链通。十项能力仍然会全报 Pending，因为载体文档还没挂。
这是设计如此——`capabilities: []` 会同时报 `ReadinessCapabilitySetInvalid`
和十个 `…Pending`，不给"只做一半就放行"留缝。
