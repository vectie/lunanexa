# 集群形态的一键部署

这份目录是 LunaNexa **唯一**的集群部署入口。它取代此前散落在管理节点家目录里的一堆
一次性脚本（`enroll-sparks.py`、`label-sparks.py`、`roll-node-r4*.sh`、`import-r4-local.sh`、
`switch-cx7-addr.sh`、`rebuild-control-image.py`……），那些脚本里有大量已经过期的副本，
而且互相矛盾。

## 一种形态，没有第二种

| 维度 | 这一版的唯一取值 | 为什么不是别的 |
| --- | --- | --- |
| 节点 agent 载体 | 每节点一个 `Deployment`（`lunanexa-node-agent-<node>`） | `DaemonSet` 无法给每个节点挂不同的 inventory / runtime 配置；`deploy/node-daemonset.yaml` 属宿主机文件形态，本集群不用它 |
| 运行时后端 | `LUNANEXA_RUNTIME_BACKEND=kubernetes` | 运行时由 Kubernetes API 拉起，宿主机上不需要任何容器引擎；现场宿主机只有 docker，而镜像里连 `sh` 都没有，OCI 形态在这套部署里从来不成立 |
| 容器引擎 | **无** | 上面的后果。OCI 形态（`deploy/lunanexa-node.env.example` + `deploy/systemd/lunanexa-node.service`）是宿主机形态，本集群不使用 |
| 节点身份 | `ServiceAccount/lunanexa-node` | 原来仓库里另有一个 `lunanexa-managed-node`，而集群里从来只存在前者 |
| 运行时命名空间 | `lunanexa-managed-runtime` | 文档里出现过第三种拼法 `lunanexa-runtimes`，已统一 |
| 每节点配置 | ConfigMap：`lunanexa-node-inventory-<node>`、`lunanexa-node-runtime-<node>` | 宿主机形态把这些放在 `/etc/lunanexa` 的 hostPath 里，那种形态本集群不用 |
| 集群描述 | `deploy/cluster/cluster.json` | 节点清单、CX7 配对、fabric 地址、镜像标签、运行时参数都在这一个文件里 |

## 用法

脚本在**管理节点**上、从本仓库的 checkout 里运行，执行用户需要能 sudo。

```sh
# 只做体检，不改任何东西
bash deploy/cluster/one-click.sh --phases preflight

# 全流程（默认就是这些阶段，按顺序）
bash deploy/cluster/one-click.sh

# 只收敛一台节点
bash deploy/cluster/one-click.sh --phases config,rbac,apply --node spark-25e2-3d35c8fd

# 先看会改什么
bash deploy/cluster/one-click.sh --dry-run
```

阶段：`preflight`（体检）、`build`（编控制面）、`images`（重打/导入镜像）、
`dra`（让 DRA 驱动镜像在每台 GPU 节点上就位）、`config`（每节点凭据/清单/运行时配置/
主机状态目录/fabric 声明）、`rbac`、`apply`、`verify`（对照 `cluster.json` 校验在线状态）。

`--credentials FILE`（默认 `~/lunanexa-cluster-credentials.json`）放 sudo 口令，
**不在仓库里**；`cluster.json` 里不含任何口令。渲染结果留在
`/tmp/lunanexa-cluster/current/rendered/`，可直接 review。

所有阶段幂等：重复运行不会轮换已有凭据、不会重建已有的 Secret、不会重复声明地址。

## 三个阻塞的根因与处理

**1. GPU 怎么分配：不用 DRA，用设备插件（已改）**

仓库的渲染器原来只会走 DRA（`gpu.nvidia.com` 设备类 + ResourceClaimTemplate）。
但现场事实是：4 台 GPU 节点上 DRA kubelet 驱动起不来（镜像拉不到），而
**nvidia 设备插件**在跑、而且在服务的每个模型 Pod 都是靠它拿 GPU 的
（`nvidia.com/gpu` + `runtimeClassName: nvidia`）。所以这不是"换个镜像"的问题，
是"平台假定了一种这台集群没有的分配机制"。

现在 `RuntimeSettings` 多了一条可选路径：给了 `device_plugin_resource`（本例
`nvidia.com/gpu`）就渲染成计数型扩展资源、加 `runtimeClassName`、**不再**生成
ResourceClaimTemplate；`devices` 里被签名钉住的那几张卡通过
`NVIDIA_VISIBLE_DEVICES` 精确指定，所以"分配哪张卡"这件事没有被放弃。
`controller_namespace` 同理：它让运行时**按命名空间**接受控制器，而不是写死一个
每次重建都会变的 Pod 地址。

配套地，`preflight` 现在检查的是**节点是否真的广播那个扩展资源**（本例 4/4 都是
`1 x nvidia.com/gpu`），DRA 阶段从脚本里删掉了——它在本集群没有意义。

**2. 节点镜像重建不了（已修）**

三件事让它不可重建，现在都补上了：

- **缺源码**：`lunanexa-loopback-proxy` 这个 sidecar 在镜像里存在、仓库里没有源码；
  现场只有一份没提交的 `~/lunanexa-loopback-proxy.c`。现在
  `cmd/loopback-proxy/` 有实现（MoonBit + 一个半关闭用的 C stub）和测试。
- **缺打包脚本**：镜像怎么打只存在于 `~/pkg-node-image-r4.sh`。现在
  `deploy/cluster/build-node-image.sh` 是同一套流程（单层 rootfs：agent 二进制、
  代理、nvidia-smi、宿主机 glibc/NSS/NVML、ca 证书、passwd/group/nsswitch），
  只是参数化并进了仓库。
- **缺可复现的构建环境**：4 台里只有 **.176** 还留着完整 arm64 工具链
  （`~/moon` 含 core bundle）和 `~/src`。`stage-and-build-node.sh` 能把工具链、
  mooncakes 快照、libpq deb 从管理节点铺到任意一台 Spark 并完成构建；
  .178 上这次就是这么铺的（注意工具链 tar 不能 `--strip-components`，
  否则 core bundle 会被剥掉、报 `Cannot load the core file`）。

**3. 控制面地址会漂（已消）**

运行时的 NetworkPolicy 原来只能点名控制面的 **Pod IP**（控制面不是 host network，
这个地址每次重建都变）。既然策略的意图是"只有控制面能进来"，现在改用
**namespaceSelector**（`kubernetes.io/metadata.name: lunanexa`），地址可以完全不给；
两者同时给也支持（集群外的控制器用得上）。`controller_addresses` 因此不再必须非空
——只要有一个 peer 就够，两个都没有才会被拒。

## 还有一件与平台无关、但同样会拦住"真的跑起来"的事

kubelet **拉不到私有 registry**（`lunanexa-registry-private` 的 NetworkPolicy 只放行控制面
Pod 与 staging）。所以任何要作为 `assignment.runtime` 起来的模型运行时镜像，都必须像节点
agent 镜像一样**先在节点上本地导入**。`images` 阶段已经有这套导入逻辑（节点镜像走的就是
它），但"把某个模型运行时的镜像导到该链路的每台节点"还没有对应的阶段，因为目前还没有
这样一个镜像存在。这是让平台真的服务一个模型之前必须补的一步。

## 仍然没做的

- 本集群**不用 DRA**，所以 `deploy/kubernetes-runtime.example.json` 里的
  `device_class_name` 只是沿用字段，不会生效；要切回 DRA 只需去掉
  `device_plugin_resource`。
- 半关闭：MoonBit 的 socket API 表达不了 `shutdown(SHUT_WR)`，`cmd/loopback-proxy`
  为此带了一个 24 行的 C stub。这是仓库里第三个同类 stub（另两处在
  `workspace/webide`、`cmd/identity-gateway`）。

## 私有 registry（`registry` 阶段）

集群里一直有一个 registry（`lunanexa-registry`，ClusterIP `10.43.216.245:5000`，TLS 由私有 CA 签），
但**没有任何节点能用它**：放行策略里写的是 `192.168.2.180/32` 和 `10.42.1.0/32`——两个已经不存在的
节点地址；节点上也没有信任材料。于是所有镜像都靠 scp + `ctr images import` 送过去。

`registry` 阶段一次把这条路易主：

1. **放行按 Pod 网段**（`registry-pull.yaml`，`10.42.0.0/16`）。原因是 kube-proxy 对集群内源地址
   不做 masquerade：registry 看到的源地址是**客户端节点的 flannel 地址**（`10.42.<node>.0`），
   不是节点的 LAN 地址。按地址逐个列，就是它上次腐烂的原因；写网段则新增节点自动成立。
   代价要说清楚：registry **没有鉴权**，这条策略就是唯一的访问控制，放开网段等于放开给集群里
   所有 Pod。要按租户收紧，得先给 registry 加认证。
2. **每台节点的信任与解析**：装 CA 到 `/etc/rancher/k3s/lunanexa-registry-ca.crt`，
   在 `/etc/hosts` 里钉 ClusterIP（kubelet 在节点上解析，不走 CoreDNS），
   用渲染出来的 `registries.yaml` **整体重写**（原来的做法是追加，会在已有 `configs:` 的文件里
   产生第二个同名顶层键，YAML 就废了），然后重启 `k3s-agent`。
3. **发布平台自己的镜像**并把节点 agent 切到 registry 引用（`lunanexa/node:20260920-arm64-r5`
   现在是从 registry 拉的，不再是 tarball）。
4. **验证**：删掉节点本地副本后真的从 registry 拉一次，四台都过。

一个坑记在这里：`ctr` 不读 k3s 的 `registries.yaml`，它要的是 k3s 生成出来的
`certs.d` 目录（`--hosts-dir /var/lib/rancher/k3s/agent/etc/containerd/certs.d`），
否则 push/pull 会报 `x509: certificate signed by unknown authority`。

## 模型列表（`scripts/adopt-model-store.py`）

控制台的模型列表读的是 `GET /v1/registry`，而 `/data/models` 里的 15 个模型只进到了
model-source 的 import 存储（都是 `Verified`），**从未被 adopted**，所以列表里只有 2 个。
另外控制台两个地方各写了一份 adopt 判定，`ui` 那份接受 `modelstore://`、`cmd/console` 那份
只接受 `s3://`——按钮渲染出来了，点下去必然被拒。现在判定只有 `ui` 一份（`pub fn
model_import_adoptable`），`cmd/console` 调用它。

`scripts/adopt-model-store.py` 用**控制台按钮调用的同一个端点**把这 17 个已验证 import 走完
adopt（每个的 license 用 store 从上游仓库记下来的真实值，显存下限用 store 校验过的字节数），
registry 里因此有 19 个模型 id。它**不做** license 接受、verification、evaluation、approval——
那四步要真凭据，编造比留白更糟。

## 与仓库其余部分的关系

- `deploy/node-kubernetes-rbac.yaml` 现在是这份脚本渲染的模板（`lunanexa-node` +
  `${RUNTIME_NAMESPACE}`），不再是另一套平行定义。
- `deploy/node-daemonset.yaml` 与 `deploy/lunanexa-node.env.example` 保留，但它们描述的是
  **宿主机形态**（凭据与清单在宿主机的 `/etc/lunanexa`），本集群不采用；两者的文件头都
  写明了这一点。
- `docs/CX7_PAIR_TOPOLOGY.md` 记录 CX7 配对能力的实现与现场状态，
  `docs/DEPLOYMENT.md` 是完整的产品级安装说明（含宿主机形态）。
