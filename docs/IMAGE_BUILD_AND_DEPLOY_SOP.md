# 镜像构建与部署 SOP

这份文档是**照着做就能上线**的操作序列。它记录的是"这个集群上真正有效的做法"，
不是通用建议：管理节点没有 docker，registry 靠私有 CA，节点镜像必须本地导入或被推送。

写它的原因很直接 —— 这套流程每次都被重新摸索一遍，而摸索的代价是节点掉线几分钟
（见第 9 节，本会话真实发生过两次）。

---

## 1. 三台机器的角色与前提

| 角色 | 机器 | 有什么 | 没有什么 |
| --- | --- | --- | --- |
| 管理节点 | `192.168.2.175`（`ubuntu`，x86_64，k3s server） | `ctr`、k3s、`~/moon-public/toolchains/moon-linux-amd64`、`~/spark-build/`、`~/lunanexa-cluster-credentials.json` | **docker / podman / nerdctl / buildah / skopeo / buildkit 全部没有**（k3s 用内置 containerd） |
| 构建 spark | `.176`（`wlc001s`，aarch64） | `~/moon`（arm64 工具链）、`~/src`（节点 agent 源码与 `_build`）、`~/stage` | 连不上 `cli.moonbitlang.cn`，**不能在那里下载工具链** |
| 计算 spark | `.177`–`.179` | 运行时 | 同上 |

**k3s 不需要 docker。** 任何时候判断"能不能打镜像"，看 `ctr`（`/usr/local/bin/ctr` 和 `k3s ctr`），
不要因为 `which docker` 为空就以为路走不通 —— 免 docker 打镜像是这个仓库的既有做法
（`deploy/cluster/build-control-image.py` 就是），控制台那份见 `scripts/deploy/build-web-image.py`。

**源码树。** 管理节点上 `~/lunanexa-deploy-src` 是这份仓库的副本（从 GitHub clone 或打包上传）。
一切都是从它跑；`one-click.sh` 默认却指向 `~/control-build/src`，**所以每次都要显式给
`LUNANEXA_SOURCE_TREE`**，否则你会拿旧源码构建而毫无提示（本会话踩过）。

```sh
export LUNANEXA_SOURCE_TREE=$HOME/lunanexa-deploy-src
cd "$LUNANEXA_SOURCE_TREE"
```

**打包源码的坑**：从 macOS 传树过去必须 `COPYFILE_DISABLE=1 tar czf ... --exclude='._*'`。
否则 AppleDouble 的 `._*.mbt` 会被编译器当二进制读，报
`Could not read the file because it contains invalid UTF-8 streams` —— 而 `moon check`
最后一行是 `0 warnings, 0 errors`，看起来完全像别的问题。

---

## 2. 铁律：先在 registry 里证明它，再改引用

**这是本节最重要的三行。** 本会话的两次故障都是违反它造成的：

```
1. 构建产物 → 导入 containerd → 标记成目标名 → 推送 registry
2. 证明：把本地那份删掉，再从 registry 拉回来（不是"本地有"就算数）
3. 只有第 2 步过了，才允许改 cluster.json / Deployment 的镜像引用
```

```sh
# 第 2 步的确切写法
S k3s ctr -n k8s.io images rm  "$REF"
S k3s ctr -n k8s.io images pull --hosts-dir /var/lib/rancher/k3s/agent/etc/containerd/certs.d \
    --platform linux/arm64 "$REF"
```

`ctr` 不读 k3s 的 `registries.yaml`，**必须**给 `--hosts-dir /var/lib/rancher/k3s/agent/etc/containerd/certs.d`，
否则报 `x509: certificate signed by unknown authority`。

### 回滚命令（记在随手能拿到的地方）

```sh
# 节点 agent：回到上一个镜像 tag（注意两个容器共用同一镜像，必须一起改）
D=lunanexa-node-agent-spark-25e2-3d35c8fd
S kubectl -n lunanexa set image deploy/$D \
    node-agent=$REG/lunanexa/node:<上一个tag> \
    control-loopback-proxy=$REG/lunanexa/node:<上一个tag>

# 控制面 / 控制台：直接回退 revision
S kubectl -n lunanexa rollout undo deploy/lunanexa-control
S kubectl -n lunanexa rollout undo deploy/lunanexa-console
```

**容器名**（猜错会静默失败，因为 `set image` 的报错常被 `2>/dev/null` 吞掉）：

| Deployment | 容器 |
| --- | --- |
| `lunanexa-node-agent-*` | `node-agent`、`control-loopback-proxy`（**两个，同一镜像**） |
| `lunanexa-control` | 用 `jsonpath` 取，别猜 |
| `lunanexa-console` | `console` |

```sh
S kubectl -n lunanexa get deploy <name> -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" "}{.image}{"\n"}{end}'
```

---

## 3. 工具链

三处必须同版本，否则轻则白名单/语法不兼容，重则整个树编译不过。当前：**`0.1.20260920`**。

| 位置 | 用途 |
| --- | --- |
| `~/moon-public/toolchains/moon-linux-amd64` | 管理节点上构建 `cmd/control` 等 |
| `~/spark-build/moonbit-linux-aarch64.tar.gz` | 铺到 spark 构建节点 agent |
| （开发机）`~/.moon` | 本地门禁 |

### 3.1 更新 x86_64（管理节点）

```sh
T=~/moon-public/toolchains/moon-linux-amd64
cp -a "$T" "$T.backup-$(basename $("$T/bin/moon" version | awk '{print $2}'))"   # 旧版上游可能已 404，备份是唯一退路
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh -o /tmp/moon-install.sh
MOON_HOME="$T" bash /tmp/moon-install.sh     # 需要 TTY？不需要，这个脚本可以直接跑
"$T/bin/moon" version
```

`moon upgrade` **不可用**：`-f`/`-q`/`--dev` 都要交互式 TTY，`script(1)` 也不行。

### 3.2 更新 aarch64（给 spark 的包）

官方包里**没有 `registry/`**，离线解析依赖图会失败（`module was not found in the registry`，
或 `no version satisfies requirement vectie/moonleaf`）。必须把管理节点的 `~/.moon` 里的
`registry/` 和 `credentials.json`（私有模块用）一起打进去。

```sh
# ① 管理节点下载（spark 连不上这个站点）
D=~/arm64-toolchain; mkdir -p $D; cd $D
curl -fsSL -o moonbit-linux-aarch64.tar.gz https://cli.moonbitlang.com/binaries/latest/moonbit-linux-aarch64.tar.gz
curl -fsSL -o core-latest.tar.gz           https://cli.moonbitlang.com/cores/core-latest.tar.gz
# .cn 会挂住，用 .com（仓库 scripts/deploy/stage-moonbit-linux-amd64.sh 用的也是 .com）

# ② 送到 .176，在那里装 + bundle core（core 必须在目标架构上 bundle）
scp $D/*.tar.gz wlc001s@192.168.2.176:/tmp/
ssh wlc001s@192.168.2.176 'set -e
  M=$HOME/moon-new; rm -rf $M; mkdir -p $M; rm -rf $M/lib $M/include
  tar xzf /tmp/moonbit-linux-aarch64.tar.gz -C $M; chmod -R u+x $M/bin
  rm -rf $M/lib/core; tar xzf /tmp/core-latest.tar.gz -C $M/lib
  export MOON_HOME=$M PATH=$M/bin:$PATH
  moon version
  moon -C $M/lib/core bundle --warn-list -a --all
  moon -C $M/lib/core bundle --warn-list -a --target wasm-gc --quiet
  tar czf /tmp/arm64-new.tar.gz -C $M .'          # 顶层必须是 bin/ lib/，不能带包装目录

# ③ 把 registry + credentials 合并进去，再打包（这一步漏了 spark 上一定构建失败）
tar czf /tmp/moon-deps.tgz -C ~/.moon registry credentials.json
scp /tmp/moon-deps.tgz wlc001s@192.168.2.176:/tmp/
ssh wlc001s@192.168.2.176 'set -e; M=$HOME/moon-new; rm -rf $M/registry; tar xzf /tmp/moon-deps.tgz -C $M; tar czf /tmp/arm64-new.tar.gz -C $M .'

# ④ 换到 spark-build（先备份）
cp -a ~/spark-build/moonbit-linux-aarch64.tar.gz ~/spark-build/moonbit-linux-aarch64.tar.gz.before-<版本>
ssh wlc001s@192.168.2.176 'cat /tmp/arm64-new.tar.gz' > ~/spark-build/moonbit-linux-aarch64.tar.gz
ls -la ~/spark-build/moonbit-linux-aarch64.tar.gz
```

---

## 4. 节点 agent 镜像（最长的一条链）

```sh
export LUNANEXA_SOURCE_TREE=$HOME/lunanexa-deploy-src
cd "$LUNANEXA_SOURCE_TREE"
S(){ echo 'vectie!@1234fsc' | sudo -S "$@" 2>/dev/null; }
REG=lunanexa-registry.lunanexa-registry.svc.cluster.local:5000
HOSTS=/var/lib/rancher/k3s/agent/etc/containerd/certs.d
TAGV=20260921-arm64-r11          # 递增；不要复用已有 tag
TAG=lunanexa-node:$TAGV
REF=lunanexa/node:$TAGV

# ① 铺源码+工具链到 .176 并在那里构建 cmd/node（不是交叉编译）
cp -f /tmp/lunanexa-src.tgz ~/lunanexa-src.tar.gz    # 用干净包，见 §1
bash deploy/cluster/stage-and-build-node.sh 192.168.2.176 wlc001s "$HOME/lunanexa-src.tar.gz"
#   期望最后是 BUILD-OK + node.exe 与 lunanexa-loopback-proxy-arm64 的 ls 输出

# ② 在 .176 上打镜像（读 ~/src 的产物）
ssh wlc001s@192.168.2.176 "bash -s -- --tag $TAG" < deploy/cluster/build-node-image.sh
#   期望 NODE-IMAGE-OK <tag> <archive> layer=<sha>

# ③ 取回、导入、标记、推送
TAR=$(ssh wlc001s@192.168.2.176 'ls -t ~/lunanexa-node-*.oci.tar | head -1')
scp wlc001s@192.168.2.176:$TAR /tmp/node-image.tar
S k3s ctr -n k8s.io images import --all-platforms --digests /tmp/node-image.tar   # 少 --all-platforms 就报 "image might be filtered out"
S k3s ctr -n k8s.io images tag --force "$TAG" "$REF"        # 必须按目标名 tag，否则 push 报 not found
S k3s ctr -n k8s.io images tag --force "$TAG" "docker.io/library/$TAG"
S k3s ctr -n k8s.io images push --hosts-dir $HOSTS --platform linux/arm64 "$REF"

# ④ 证明它真的在 registry 里（§2）
S k3s ctr -n k8s.io images rm "$REF"
S k3s ctr -n k8s.io images pull --hosts-dir $HOSTS --platform linux/arm64 "$REF"

# ⑤ 只有 ④ 过了才改描述，然后收敛
python3 - <<'PY'
import json
p="deploy/cluster/cluster.json"; d=json.load(open(p))
d["images"]["node"]=f"lunanexa-registry.lunanexa-registry.svc.cluster.local:5000/lunanexa/node:<TAGV>"
for e in d["registry"]["publish"]:
    if e["target"].startswith("lunanexa/node:"):
        e["source"]=f"lunanexa-node:<TAGV>"; e["target"]=f"lunanexa/node:<TAGV>"
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False); open(p,"a").write("\n")
PY
bash deploy/cluster/one-click.sh --credentials ~/lunanexa-cluster-credentials.json --phases config,rbac,apply

# ⑥ 验证（两个容器都要在跑）
S kubectl -n lunanexa get pods | grep node-agent        # 期望 4 × 2/2 Running
S kubectl -n lunanexa logs deploy/lunanexa-node-agent-spark-25e2-3d35c8fd -c node-agent --tail=50 | grep -c 'HTTP 400'
```

**新增指标时要一起做的**：`telemetry/telemetry.mbt` 的白名单在**控制面**里。
只滚节点 agent 会让新指标被 `PUT /v1/telemetry -> HTTP 400` 丢掉 → 见 §5。

---

## 5. 控制面镜像（telemetry 白名单 / API）

**这个 tag 是设计成原地覆盖的。** `build-control-image.py` 的 `--base-image` **默认等于 `--image`**，
所以 `cluster.json images.control` **绝对不能 bump 成新 tag**，否则它会拿自己当基准去 export，
报 `ctr: image "lunanexa-control:<新tag>": not found`。

```sh
export LUNANEXA_SOURCE_TREE=$HOME/lunanexa-deploy-src
cd "$LUNANEXA_SOURCE_TREE"

# ① 记录旧镜像 digest（用来判断是否真的换了）
BEFORE=$(S k3s ctr -n k8s.io images ls | grep 'lunanexa-control:20260918' | awk '{print $3}' | head -1)

# ② 构建 + 覆盖同一个 tag
bash deploy/cluster/one-click.sh --credentials ~/lunanexa-cluster-credentials.json --phases build,images
#   期望 CONTROL-IMAGE-OK lunanexa-control:20260918 <archive>

# ③ 确认 digest 变了，再重启
AFTER=$(S k3s ctr -n k8s.io images ls | grep 'lunanexa-control:20260918' | awk '{print $3}' | head -1)
[ "$BEFORE" != "$AFTER" ] && S kubectl -n lunanexa rollout restart deploy/lunanexa-control
S kubectl -n lunanexa rollout status deploy/lunanexa-control --timeout=180s

# ④ 验证新指标被接收（1–2 分钟一次上报间隔）
curl -s -m 15 http://127.0.0.1:4174/v1/telemetry | python3 -c "
import json,sys,collections
d=json.load(sys.stdin); c=collections.Counter(s['metric'] for s in d.get('samples',[]))
print('cpu:', 'host_cpu_utilization_per_mille' in c, ' mem:', 'host_memory_used_mib' in c)
print(', '.join(sorted(c)))"
```

回滚：`S kubectl -n lunanexa rollout undo deploy/lunanexa-control`。

---

## 5.1 身份网关镜像（docker-free 重建）

**背景（2026-09-22 实测）**：身份网关 `cmd/identity-gateway` 的作者脚本
`scripts/deploy/build-management-images.sh` 用的是 `docker build`，而**管理节点上没有
docker/podman/nerdctl/buildah**（`command -v` 四个全空）。所以那条路在本机走不通，
必须用 `ctr` 手法（和 §5 的控制面镜像同源）。

**镜像长什么样**（`images/Containerfile.identity-gateway`）：

```
构建阶段：moon build cmd/identity-gateway --target native --release --jobs 1
产物：    _build/native/release/build/cmd/identity-gateway/identity-gateway.exe
运行阶段：FROM lunanexa/runtime-base:bookworm-amd64
          COPY … → /usr/local/bin/lunanexa-identity-gateway
          USER 65532:65532
          ENTRYPOINT ["/usr/local/bin/lunanexa-identity-gateway"]
```

**不能用 `build-control-image.py` 代劳。** 它把二进制名硬编码成
`BINARY_NAMES = ("lunanexa-control", "lunanexa-loopback-proxy")`，
打进网关镜像会得到错误的名字与入口。网关需要一个同手法的独立覆盖步骤。

**源码树的两个坑（都实测过）**：

- `~/lunanexa-deploy-src` **不是 git checkout，而且是残缺树** —— 只有 `deploy/ database/
  deployment/ desktop/ docs/ docs-site/ extensions/ guide_monitor/`，
  **连 `cmd/` 都没有**。想改 `cmd/identity-gateway` 必须换到完整源码树
  （如 `~/luna-src-next`）或先把修好的文件送过去。
- 节点上 `~/.moon/bin` 为空，linux-amd64 工具链要先铺：
  `sh scripts/deploy/stage-moonbit-linux-amd64.sh`
  （从 `cli.moonbitlang.com` 下载并校验两个 sha256；**`.cn` 会挂住，用 `.com`**）。

**顺序（遵守 §2 铁律，一步一步来）**：

```sh
# ① 把带修复的源码放到节点上的完整源码树，并确认这一行是带引号的
grep -n 'expires_unix_ms' cmd/identity-gateway/server.mbt      # 期望看到 \"\{…}\"

# ② 铺 linux-amd64 工具链 + core（core 必须在目标架构上 bundle）
sh scripts/deploy/stage-moonbit-linux-amd64.sh

# ③ 构建（产物路径见上）
moon build cmd/identity-gateway --target native --release

# ④ 覆盖进镜像：用仓库里的 deploy/cluster/build-identity-gateway-image.py
LUNANEXA_SUDO_PASSWORD=... python3 deploy/cluster/build-identity-gateway-image.py \
  --image lunanexa/identity-gateway:<tag> \
  --base-image "<Deployment 里现在用的那个 ref>" \
  --binary ~/luna-src-next/_build/native/release/build/cmd/identity-gateway/identity-gateway.exe \
  --work ~/gw-build/image
#    期望 GATEWAY-IMAGE-OK <tag> <archive>
#    （它是从 build-control-image.py 派生的，差异与坑都写在脚本头和下面）

# ⑤ 证明它真的在 registry 里：把本地那份删掉，再从 registry 拉回来
S k3s ctr -n k8s.io images rm  "$REF"
S k3s ctr -n k8s.io images pull \
    --hosts-dir /var/lib/rancher/k3s/agent/etc/containerd/certs.d \
    --platform linux/amd64 "$REF"

# ⑥ 只有 ⑤ 过了才改 Deployment 的镜像引用，然后收敛
S kubectl -n lunanexa rollout status deploy/lunanexa-identity-gateway --timeout=180s
```

**实测踩过的三个坑（都是这一步的，别再重踩）**：

1. **`MOON_HOME` 指错会伪装成依赖问题。** 把 `MOON_HOME` 指向
   `~/moon-public/toolchains/moon-linux-amd64` 时，`moon build` 报
   `Failed to resolve registry dependency \`vectie/moonleaf\` … no version satisfies requirement \`0.1.15\``，
   看起来像源码问题，其实是那个工具链目录自带的 registry 索引太旧。
   正解：`MOON_HOME` 留在带 registry 的 `~/.moon`（它里面就有 `vectie/moonleaf/0.1.15`），
   再把暂存工具链借给它：
   `ln -sfn <toolchain>/bin ~/.moon/bin && ln -sfn <toolchain>/lib ~/.moon/lib`。
2. **层级清单要用 `isfile()` 取，不要用"去掉斜杠后缀"过滤。**
   某些归档里的目录项名字**不带**结尾斜杠，于是会被当成"非二进制文件"，
   让 `is_binary_layer` 永远返回 False，报
   `could not find a binary layer … is it a LunaNexa identity-gateway image?`。
3. **manifest 的 `mediaType` 必须一并改成 OCI。** 如果 base 是 Docker schema2 清单
   （`application/vnd.docker.distribution.manifest.v2+json`），而你把层和 index 条目改成 OCI 了，
   注册表会以 **400 `manifest invalid`** 拒收：
   `if present, mediaType in manifest should be 'application/vnd.oci.image.manifest.v1+json'
   not 'application/vnd.docker.distribution.manifest.v2+json'`。
   **而 `ctr images push` 会照样打印 complete** —— 这是"铁律"必须执行的原因。
4. **找不到可替换层时就追加，不要失败。** 层是 last-wins 叠加的，
   新二进制放在最后一层即可遮住旧的；"删掉旧层"只是体积优化，
   而且依赖 base 的层布局（本次 base 只有 1 层且混着目录项）。

**验证镜像里确实是新二进制**（不要只看 `GATEWAY-IMAGE-OK`）：

```sh
sha256sum <built>/identity-gateway.exe            # 与镜像里那层比对
# 本次实测：built=1a82244e…，新镜像最后一层里的 /usr/local/bin/lunanexa-identity-gateway
# 同为 1a82244e…，而它下面那层是旧的 2064624 字节版本
```

**回滚**：`S kubectl -n lunanexa rollout undo deploy/lunanexa-identity-gateway`。

**当前引用形态**：Deployment 用的是 registry **digest** 而不是 tag ——
`lunanexa-registry.lunanexa-registry.svc.cluster.local:5000/acceptance/identity-gateway@sha256:79b5bce3…`。
所以"换个 tag"这一步在本例里等于换 digest，改引用前务必先完成 ⑤ 的拉回验证。

---

## 6. 控制台镜像（UI）

控制台是 **nginx 镜像里烤着浏览器 bundle**（`images/Containerfile.web` 只做 `COPY _build/browser-dist/`）。
bundle 只需要 `moon`；把它变成镜像在**没有 docker 的机器上**用 `scripts/deploy/build-web-image.py`
（和 `build-control-image.py` 同一手法：export → 追加一层 → 重组 OCI → import）。

```sh
export LUNANEXA_SOURCE_TREE=$HOME/lunanexa-deploy-src
cd "$LUNANEXA_SOURCE_TREE"

bash scripts/build-browser-bundles.sh                 # 只需 moon；产出 _build/browser-dist (约 15M)

# 把部署自己的两个 opt-in 渲染进去。**必须做**：bundle 里两个 meta 都是空的，
# 不渲染的话明文 HTTP 下每个按钮都是灰的、控制台只会停在登录页。
python3 scripts/deploy/render-public-http-origin.py \
    --dist _build/browser-dist \
    --origin console=http://106.39.18.146:4174 \
    --origin enterprise=http://106.39.18.146:5002 \
    --operator-open console=*
#   --origin        = 该页面被服务的**精确** origin；明文 HTTP 下凭证只在这个 origin 上放行
#   --operator-open = 该页面**跳过登录门**，由同源代理附加运维权限
#                     `*` 表示"任何能加载这个页面的 origin 都算运维"——这是部署决定，不是默认值
#                     源码里 meta 是空的，只有这个脚本会填它

python3 scripts/deploy/build-web-image.py \
    --base  lunanexa-web:20260921 \
    --image lunanexa-web:20260922 \
    --dist  _build/browser-dist \
    --sudo-password 'vectie!@1234fsc'
#   期望 WEB-IMAGE-OK ... (N files, M whiteouts)

S kubectl -n lunanexa set image deploy/lunanexa-console console=lunanexa-web:20260922
S kubectl -n lunanexa rollout status deploy/lunanexa-console --timeout=120s

# 验证：服务出去的 js 必须与构建产物同 sha256
curl -s http://127.0.0.1:4174/console/console.js | sha256sum
sha256sum _build/browser-dist/console/console.js
```

**两条不要忘**：

- **免登录（`--operator-open`）需要代理那边同时具备三样东西**，少一样就退回登录页或 401：
  1. 控制面有一个**非 bootstrap** 的运维令牌 —— `LUNANEXA_OPERATOR_TOKENS=console-proxy=<tok>`。
     bootstrap 那个（`LUNANEXA_OPERATOR_TOKEN`）在**存在任何 `PlatformOperator` 账户之后会被作废**
     （`ApiService::operator_identity` 的 `bootstrap_retired` 分支），所以一旦建了运维账户，
     代理注入它就会 401 —— 这是"免登录突然坏掉"最常见的原因。
  2. 代理的 `map $http_authorization` 要把**空 header** 和**控制台在 open 模式发的
     `Bearer deployment-open` 标记**都映射成那个令牌；`default` 必须保留 `$http_authorization`，
     否则真实会话（`lnxs_…`）会被顶掉，而伪造令牌也会被放行。
  3. 控制面 `/v1/audit` 由代理单独注入审计令牌，控制台不需要浏览器持有审计凭据。

- **不要 prune** html 根里 bundle 没有的文件。bundle 由 `build-browser-bundles.sh` 产出，
  但那个目录还装着**私有合同字体**（`assets/fonts/private/`，仓库里没有，是授权字体）和
  **合同预览图**（`console/contract-previews/`）。删掉它们合同渲染就坏了。
  脚本默认只清 macOS 垃圾并**报出**留下的数量；`--prune` 是破坏性选项。
- 控制台的 nginx 根就是 html 根：字体在 **`/assets/...`**，不在 `/console/assets/...`；
  另注意 4174 代理**没有** `/workbench/` 的 location，所以 `/workbench/workbench.js` 是 404（既有问题）。

---

## 7. H3 服务端补丁（MiniMax-H3）

补丁以 configmap 挂进 pod，靠容器 args 里的 `cp` 覆写，**镜像不动**。每次都要重启 pod，
而重启要**加载 13 个权重分片、约 11 分钟**。

```sh
cd /tmp/lunafix3          # 或重新上传 deploy/acceptance/patches + 脚本
./patch-vllm-omni-h3-encode.sh 'vectie!@1234fsc' minimaxh3-fl2va
./patch-vllm-omni-h3-encode.sh 'vectie!@1234fsc' minimaxh3-ref2va
#   脚本自带：队列非空时硬拒绝重启；progressDeadlineSeconds 抬到 1800；末尾校验容器内 md5
```

**注意**：`patch-api-server-progress.py` 是**带断言的定位替换**（api_server.py 有 3500 行，
不适合整文件入仓）。它幂等，重复跑只会把封顶值归一到 `CAP`（当前 80）。
`--rebuild-node-image` 无关；这两个 deployment 与节点 agent 是分开的。

验证：

```sh
S kubectl -n lunanexa exec <pod> -- grep -c _live_video_progress \
    /usr/local/lib/python3.12/dist-packages/vllm_omni/entrypoints/openai/api_server.py   # 期望 2
```

两个容易搞错的点：补丁写出的 `/tmp/vllm_progress.json` 在 **pod 内**，不是宿主的 `/tmp`；
而补丁文件在容器里，所以查它要用 `kubectl exec`（没有 docker，也没有 `docker exec` 可用）。

---

## 8. ComfyUI 节点补丁与模板

```sh
cd /tmp/lunafix3
./patch-comfyui-vllm-omni-node.sh 'vectie!@1234fsc'    # 3 个模块 + 队列非空硬闸，重启约 40 秒
```

模板（**仓库为准**，改仓库再同步，别直接改宿主）：

```sh
bash deploy/acceptance/install-comfyui-templates.sh
#   单向同步 + prune 掉仓库里没有的 + 对照 /api/workflow_templates 校验 + 断言图接线
```

模板是**按请求读目录**的，加/改文件**不需要重启 ComfyUI**。
取正文的路由是 `/api/workflow_templates/<module>/<文件名>.json`（索引里的名字**去掉了 `.json`**；
不带后缀会 404）。

---

## 9. 陷阱清单（每一条都真踩过）

| 陷阱 | 症状 | 正解 |
| --- | --- | --- |
| 先改引用后验证镜像 | `ImagePullBackOff` / `ErrImagePull`，服务掉线 | §2 的铁律 |
| `ctr import` 少 `--all-platforms` | `ctr: image might be filtered out`（像 tar 坏了） | 加 `--all-platforms` |
| `ctr push` 前没按目标名 tag | `image "<registry-ref>": not found` | 先 `images tag --force <tag> <REF>` 再 push |
| `ctr` 缺 `--hosts-dir` | `x509: certificate signed by unknown authority` | 指向 k3s 的 `certs.d` |
| bump 了 `images.control` 的 tag | `ctr: image "<新tag>": not found` | tag 原地覆盖 + `rollout restart` |
| 只改 agent 的 container[0] | pod 停在 `1/2` | 两个容器一起改 |
| `set image` 报错被 `2>/dev/null` 吞掉 | 以为改了其实没改 | 改完 `jsonpath` 回读确认 |
| stage 工具链没带 `registry/`+`credentials.json` | 依赖解析失败 | §3.2 |
| spark 上 `curl cli.moonbitlang.cn` | 超时 | 在管理节点下载后传过去；用 `.com` 域名 |
| macOS `tar` 带 `._*` | `invalid UTF-8 streams`，却报 `0 warnings, 0 errors` | `COPYFILE_DISABLE=1 tar --exclude='._*'` |
| `LUNANEXA_SOURCE_TREE` 没设 | 用 `~/control-build/src` 静默构建旧源码 | 每次都显式 export |
| `ls \| xargs -n1 basename` | 中文名带空格，拆成 `16:9）.json` | shell glob：`for f in dir/*.json; do basename "$f"; done` |
| `for x in $list` / `sudo -S` 抢 stdin | 文件名碎裂 / `apply -f -` 报 no objects | `while IFS= read -r`；清单落临时文件 |
| 重启 H3 前不查队列 | 打断正在跑的视频任务 | 脚本已硬闸；手工操作也要先看 `/queue` |
| 上报里的 `progress` 字段 | 完成前恒为 0（旧版行为） | 现在随去噪上升、**封顶 80**；看 pod 日志 `n/7 it/s` |
| 用 registry 里的名字做 `--image` 构建后在 Deployment 里按 digest 引用 | pod 卡 `CreateContainerError`：`failed to check if this is a checkpoint image … image "docker.io/<annotation>": not found`。kubelet 先按 config digest 反查镜像，再拿清单注解里的名字去 containerd 找，那个名字不存在就起不来 | pull 回来之后再补一个 kubelet 要的那个别名：`ctr images tag --force <REF> docker.io/<annotation>:<tag>`。§5.1 的脚本已内置这一步 |
| hostNetwork 单副本直接 `rollout restart` | 新 pod 永远 `Pending`：`didn't have free ports for the requested pod ports` | 先 `scale --replicas=0`，等旧 pod 消失，再 `--replicas=1`（`operator-4173-proxy` 就是这种） |
| 把 `LUNANEXA_OIDC_ADMIN_ORIGIN` 指向 provider 的 service 名 | `/auth/register` 一律 503，日志里是 `admin-token-transport: Connection refused`；启动时不报错，所以极易误判成代码问题 | provider 的 pod 只接受自己 edge 的连接（NetworkPolicy）。admin origin 必须是 §5.1 里那个 identity internal edge，并在那里加一个 `POST`-only 的 `/admin/realms/<realm>/users` location |
| 用 `println` 给网关加诊断 | 日志里永远看不到（stdout 有缓冲，进程不退出就不刷） | 用 `eprintln`（stderr 立即落盘）。既有的 `println` 同理，别指望它 |
| 只写空 `requiredActions: []` 就建 Keycloak 用户 | 建号成功，但立刻登录报 `400 invalid_grant / "Account is not fully set up"` —— realm 的默认 required action 会覆盖空列表 | realm 侧也清掉：`update authentication/required-actions/CONFIGURE_TOTP -r <realm> -s defaultAction=false` |
| 浏览器 bundle 重新构建后没渲染 HTTP opt-in | 页面能开，但每个输入框和按钮都是灰的，看起来像"没反应" | 构建后跑 `scripts/deploy/render-public-http-origin.py --dist _build/browser-dist --origin <page>=<origin>`；每个页面的 meta 必须等于**它自己的** origin |
| `cp -a` 把 bundle 拷进 hostPath 给 nginx 用 | 403 Forbidden：`_build` 的权限是 `760`，nginx 用户读不到 | 拷完 `chmod -R a+rX`，目录 755、文件 644 |
| 只改管理节点的 `~/portal-dist/enterprise`，未更新 `lunanexa-enterprise` 镜像 | 公网 5002 仍服务旧版 JS | 现网 5002 的 `/enterprise/` 代理到 `lunanexa-enterprise:8080`；构建镜像、推送并按摘要更新该 Deployment（见 §11） |

---

## 11. 浏览器 UI 的落点（2026-09-22 实测）

同一套 bundle 在这台机器上有**三条**不同的投放路径，改 UI 时三条都要想到：

| 入口 | 谁在服务 | 更新方式 |
| --- | --- | --- |
| `http://<host>:4174/console/` | `operator-4173-proxy`（hostNetwork nginx）→ `lunanexa-console:8080`（`moon/lunanexa-web` 镜像） | 重建 + push web 镜像，`set image deploy/lunanexa-console`，再按上表的 hostNetwork 规则重启 proxy |
| `http://<host>:5002/enterprise/` | 同一个 proxy 的 5002 server，`proxy_pass http://lunanexa-enterprise:8080` → **`lunanexa-enterprise` Deployment** | 构建 + push web 镜像，按摘要更新 `deploy/lunanexa-enterprise`；以公网 JS 的 SHA-256 对照构建产物 |
| `http://<host>:5003/console/`（经身份网关） | `lunanexa-identity-gateway` 代理到 `lunanexa-console:8080` | 同第一条 |

另外两条与 4174 有关、容易漏的：

- `location /auth/` 在 4174 上原本指向**控制面**（带一个静态 bearer）。统一登录后它必须指向
  **身份网关**，并把 `Host`/`Origin` 改写成 operator host（`106.39.18.146:5003`）——
  网关把一个会话绑定在**一个**配置的 host 上，而 4174 不是它。
- 5002 的 `/` 原本对没有 OIDC cookie 的访客 302 到 `/enterprise/?demo=1`，也就是**默认进演示态**，
  真实门户的注册/登录表单永远看不到。已改成直接 302 到 `/enterprise/`；`?demo=1` 仍可用。

---

## 12. 一次完整上线的顺序

按依赖排，不要跳：

```
0. 确认源码树、LUNANEXA_SOURCE_TREE、干净源码包
1. 工具链（§3）—— 只在需要时；三处必须同版本
2. 节点 agent 镜像（§4）→ 先把源码铺到 .176 构建
3. 控制面镜像（§5）—— 若改了 telemetry 白名单 / API，这一步必须做，否则指标会被 400 丢掉
4. 控制台镜像（§6）—— 若改了 UI
5. H3 服务端补丁（§7）—— 若改了 vllm_omni 侧的补丁
6. ComfyUI 节点补丁与模板（§8）
7. 身份网关镜像（§5.1）—— 若改了 `/auth/*` 路由或网关配置；**它和 §5 是两条不同的链**
8. 浏览器 UI（§11）—— 若改了 UI；**三条投放路径都要更新**
9. 逐项验证：节点 2/2、`/v1/telemetry` 里有预期指标、控制台 bundle sha 一致、
   模板能被 `/api/workflow_templates` 列出
```

本会话实际就是按 3 → 2 → 5 → 4 → 6 的顺序补完的，其中 3 是最后才发现必须做的那一步 ——
**新增一个遥测指标要同时动"发"和"收"两端**，`telemetry/telemetry.mbt` 的白名单在控制面里。
