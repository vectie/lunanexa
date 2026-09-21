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
   **本次已把这条链基本修通**：身份库 `1/1 Running`、Keycloak `1/1 Running`
   （Bootstrap completed）、身份边缘全部 `Running`；
   `5003/auth/oidc/start?audience=operator` 与 `5002/auth/oidc/start?audience=enterprise`
   现在都返回带 PKCE 的 302 落到 Keycloak 的登录表单，而且**企业侧已在浏览器里真正完成
   Keycloak 登录、回调换发了会话 cookie**（§2.6）。
   还剩两处：① 公网明文 HTTP 下控制台按设计拒绝管理员登录（一个部署策略开关，未替你按）；
   ② 最后一跳 `/auth/session`（cookie → `lnxs_` 租户会话）交换失败（401/503），
   企业侧因此还没有真实租户主体（§2.6 末段）。
   另外两个值得单列的问题：登录成功后前端 `location = /` 会**无条件把人送进 demo 门户**
   （§4 缺陷 #7），以及前端 ConfigMap 明文内嵌操作员令牌并注入每个 `/v1/` 请求，
   4174/5002 因此无需任何会话即可调用操作员 API（§2.5 发现 4）。
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

## 5. 卡点清单（按修复收益 / 代价排序）

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

## 8. 未验证

- 真实 OIDC 登录与首次登录建账户/受限体验。
- 真实订单提交、管理侧审批、DOCX/PDF 生成与下载、签署盖章、扫描件上传与复核。
- 权限实际开通后企业侧是否真正拿到权限。
- 管理侧的 CPU/内存等指标在浏览器中的渲染（本次控制台是实时数据，但没有逐项核对指标卡）。

本次对帐的记账口径：**"能点进去并拿到实时数据"才算一步通了**；只有页面渲染、数据来自
本地夹具或本地会话的，不计为通。
