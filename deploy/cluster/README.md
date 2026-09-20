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

## 仍然挡在前面的三件事（都已如实反映在脚本行为里）

1. **节点镜像还没从这棵树重建过。** Kubernetes 后端要求 agent 二进制在启动时拿一个
   journal owner nonce；原实现去 spawn `/usr/bin/openssl`，而 agent 镜像里没有 openssl，
   于是 agent 一起就 `OSError("@process.run(): No such file or directory")` 崩溃。
   代码已改成走 `getentropy(2)` 的 C stub（`node/kubernetes/secure_random.c`，与
   `workspace/webide` 里那套同源），**但这需要重新构建 arm64 节点镜像**。
   当前 4 台跑的是重建之前的镜像，所以 `apply` 阶段默认**拒绝**改变运行时后端，
   除非显式传 `--accept-runtime-backend-change`。这是刻意的：跳过它就会让整队在
   CrashLoop 里。
   重建的前置条件目前并不齐：spark 上原来的 arm64 构建环境（`~/moon`、`~/src`）已不存在，
   而且 `lunanexa-loopback-proxy` 这个镜像里的二进制**在仓库里没有源码**。
2. **DRA 驱动镜像拉不到。** Kubernetes 后端用 `gpu.nvidia.com` 设备类给运行时分配 GPU，
   而该驱动（`registry.k8s.io/dra-driver-nvidia/...:v0.5.0`）的管理节点只能到达前端、
   到不了 blob 后端（超时），试过的四个公共镜像源都对它 403 或没有这个仓库。
   `dra` 阶段会把源列表（`images.draSources`）逐个试过去，源可达时全自动完成；
   现在四个源都不可达，所以 4 台 GPU 节点上该驱动仍是 `ImagePullBackOff`。
3. **控制面给运行时授权用的地址是 Pod 地址。** 控制面不是 host network，运行时的
   NetworkPolicy 只能写死它的 Pod IP，而该 IP 随 Pod 替换而变。脚本在每次 `config`
   时重新取当前值（`cluster.controlPlane.authorization.deriveFrom`），但这终究是权宜；
   真正的解法是让控制面走 host network，或者把这条策略改成基于 Service 的等价物。

## 与仓库其余部分的关系

- `deploy/node-kubernetes-rbac.yaml` 现在是这份脚本渲染的模板（`lunanexa-node` +
  `${RUNTIME_NAMESPACE}`），不再是另一套平行定义。
- `deploy/node-daemonset.yaml` 与 `deploy/lunanexa-node.env.example` 保留，但它们描述的是
  **宿主机形态**（凭据与清单在宿主机的 `/etc/lunanexa`），本集群不采用；两者的文件头都
  写明了这一点。
- `docs/CX7_PAIR_TOPOLOGY.md` 记录 CX7 配对能力的实现与现场状态，
  `docs/DEPLOYMENT.md` 是完整的产品级安装说明（含宿主机形态）。
