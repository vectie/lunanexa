# CX7 双机拓扑（唯一被承认的多机形态）

状态：**选择、规划、渲染、对账四步均已实现并部署；真实双机执行受限于节点运行时后端**。

## 已完成

**第 1 步（选择侧，提交 `8fa8dda`）**

- `contracts`：`cx7_pair_topology_profile = "cx7-pair-v1"`、`cx7_pair_member_count = 2`、
  `cx7_peer_label = "lunanexa.io/cx7-peer"`、`cx7_address_label = "lunanexa.io/cx7-address"`；
- `scheduler.NodeSnapshot.cx7_peer`（由 `api` 从节点上报的标签填充）；
- `scheduler.validated_cx7_pair()`：互相指认才成对，永远返回 2 个，否则
  `PairTopologyNotValidated` / `NoValidatedCx7Pair`；
- `place()`：多机请求返回 `selected_pair`，**要么是对、要么什么都不给**，不再退回单机。

**第 2 步（门槛，提交 `e70fad6`）**

- `ModelServiceIntent.topology_profile : String?`——`None` 是单机，唯一的另一取值是 CX7 对；
- `preflight` 把 intent 与 template 放在一起判：运行时能配对但 intent 没指名 →
  `GeometryNotDeclared`；intent 指名但运行时不支持 → `RuntimeCannotPair`。

**第 3 步（规划侧，提交 `64e2534` + `f5e0bbf`）**

- `contracts.AssignmentGroup { group_id, rank, world_size, peer_endpoint }`，作为
  `DesiredAssignment.group` 与 `PlannedReplica.group` 的**一个可选字段**（rank 离开
  world_size 没有意义，所以它们同进同出）；
- `contracts.cx7_pair_members()` 是配对规则的**唯一实现**，`scheduler` 与 `deployment`
  都调用它，两边不可能各自漂移；
- `preflight` 真正**产出**一对：两个互相指认、且两端都声明了 fabric 地址的兼容节点变成
  一个逻辑实例的两个 rank。凑不出对时是 `NoCx7Pair`（Blocking），**绝不退回单机**；
  `PairExecutionNotImplemented` 已删除（不再有人产生它）。

**第 4 步（执行侧，提交 `f5e0bbf`）**

- `node/kubernetes`：带 `group` 的 assignment 渲染为 `hostNetwork: true` +
  `dnsPolicy: ClusterFirstWithHostNet`、挂载 `/dev/infiniband` 与内存态 `/dev/shm`、
  加 `IPC_LOCK` 能力，并注入 `LUNANEXA_RANK` / `WORLD_SIZE` / `PEER_ENDPOINT` /
  `SELF_ENDPOINT` / `HEAD_ENDPOINT`（head = rank 0 的地址，两个 rank 都用它做 rendezvous）；
  对端在 NetworkPolicy 里被**显式点名**，而不是把隔离去掉；
- `RuntimeSettings.fabric_address`（可选）声明本机在私有网络上的地址：**没有它就拒绝
  渲染带 group 的 Pod**，而不是起一个找不到对端的容器。单机渲染逐字节不变；
- `controller.deployment_operation_ready()`：一个 group 只有在报告上来的成员**恰好覆盖
  0..world_size-1 每个 rank 一次**时才算就绪，半个 TP 组永远不会被提升。

## 现场部署状态（2026-09-20）

两对物理上已验证的 CX7 互联，都已写进节点 inventory 的标签：

| 节点 | 节点 id | 对端 | 本机 fabric 地址 |
| --- | --- | --- | --- |
| 192.168.2.176 | `spark-25e2-3d35c8fd` | `spark-3782-feee26eb` | 192.168.100.10 |
| 192.168.2.177 | `spark-3782-feee26eb` | `spark-25e2-3d35c8fd` | 192.168.100.11 |
| 192.168.2.178 | `spark-57f5-98a504ed` | `spark-368c-0f2ee8b2` | 10.0.22.1 |
| 192.168.2.179 | `spark-368c-0f2ee8b2` | `spark-57f5-98a504ed` | 10.0.22.2 |

.176↔.177 的 192.168.100/101 双路是**声明式**的：`/etc/netplan/60-lunanexa-cx7.yaml`
（`optional: true`）声明了两条地址，netplan 每次启动生成 `netplan-enp1s0f1np1`
profile 交给 NetworkManager，重启后自动回来。

.178/.179 原来**只活在内存里**：`/etc/netplan/` 没有对应文件，
`/etc/NetworkManager/system-connections/` 是空的，唯一的 profile 在
`/run/NetworkManager/system-connections/`，mtime 正好是加地址那一刻
（.178 `enp1s0f1np1.nmconnection` 2026-09-20 14:00:46，.179 `enp1s0f0np0.nmconnection`
14:00:47），`/etc` 下没有任何文件提到这两个网口——那台机器一重启，10.0.22.x 就没了，
配对标签会随之变成假话。

现在已经照 .176/.177 的样子补上声明式配置：

```yaml
network:
  version: 2
  ethernets:
    enp1s0f1np1:                      # .179 上是 enp1s0f0np0
      addresses: [10.0.0.1/24, 10.0.22.1/24]
      optional: true
```

写入 `/etc/netplan/60-lunanexa-cx7.yaml`（0600 root），`netplan get` 已确认合并视图
读得到这两条地址。**没有执行 `netplan apply`**：两条地址现在本来就在线（GLM-5.3 正跑在
上面），apply 只会让 NetworkManager 接管，没有必要在服务运行中去动它；重启后由 netplan
自动生效。

## 仍然挡在前面的：节点运行时后端

**宿主机上根本没有 podman。** 4 台 spark 上 `command -v podman` 无输出，只有
`/usr/bin/docker`（socket 在 `/var/run/docker.sock`）和 `ctr`；GLM-5.3 的 head 现在是
宿主机上的 docker 容器（`glm53-exl3-head`、`glm53-nfs`），不是被平台拉起来的。

而仓库自己的两个部署形态里，OCI 形态假定的引擎（`deploy/lunanexa-node.env.example`）
正是 podman 的 socket：

```
LUNANEXA_RUNTIME_BACKEND=oci
LUNANEXA_CONTAINER_ENGINE=/usr/bin/podman
LUNANEXA_CONTAINER_ENGINE_ENDPOINT=unix:///run/podman/podman.sock
```

集群形态（`deploy/node-daemonset.yaml`）则相反，它设 `LUNANEXA_RUNTIME_BACKEND=kubernetes`
并且**刻意不挂任何容器 socket**——那条路不需要 podman。

现场这 4 个 agent 是第三种组合：集群形态的镜像 + OCI 形态的后端，而且 endpoint 被改成
`local://`。于是 agent 会在自己的容器里去找 `/usr/bin/podman`——那个镜像连 `sh` 都没有
（`kubectl exec` 报 `exec: "sh": executable file not found in $PATH`）。

旁证是"这条路从来没跑通过"：4 台机器上 `/var/lib/lunanexa/` 下只有 `node-agent` 状态目录，
**`models/` 缓存目录根本不存在**，`/v1/nodes` 里 4 个节点的 `running_deployments` 也是空的。
也就是说托管运行时既没在双机上跑过，也没在单机上跑过——所以"以前也不需要 podman"是对的，
podman 从来不是既有事实的一部分，它只是这套配置写在纸面上的假定。

要让配对真正跑起来，需要在节点上二选一：

1. **Kubernetes 后端**：`LUNANEXA_RUNTIME_BACKEND=kubernetes` +
   `/etc/lunanexa/kubernetes-runtime.json`（含 `fabric_address`）+ `deploy/node-kubernetes-rbac.yaml`
   里的权限 + DRA 设备类。本仓库的渲染路径已经支持配对，缺的是部署面；
2. **OCI 后端**：要么在宿主机装 podman 并把 socket 挂进 agent（按 env example 的
   `unix:///run/podman/podman.sock`），要么承认这个集群用的是 docker、把引擎换成
   `/usr/bin/docker` 并挂 `/var/run/docker.sock`；无论哪种，`local://` 都得改掉，
   并且要把配对渲染补进 `node/runtime_supervisor.mbt`（本次只补了 Kubernetes 后端）。

原始设计说明如下。

## 1. 约束（来自产品决定）

LunaNexa 只承认**一种**多机形态：

- **恰好两台**节点；
- 这两台之间必须有**已验证的 CX7 互联**；
- 不承认"任意两台"（可能根本没有高速互联，TP 会退化到管理网）；
- 不承认三台及以上。

因此多机能力不是"允许 N 个节点"，而是"承认一个名为 `cx7-pair-v1` 的**拓扑对**"。
3 台以上没有对应 profile，从结构上就表达不出来，而不是靠参数校验拦住。

## 2. 现状：脚手架已经在，但只在"拒绝"方向

| 位置 | 现状 |
| --- | --- |
| `contracts.RuntimeSpec.supports_multi_node : Bool` | 只是个布尔，说不出"哪两台、怎么连" |
| `scheduler.PlacementRequirements` | 已有 `multi_node : Bool` + `topology_profile : String?` |
| `scheduler.ScorePolicy.validated_topology_profiles : Array[String]` | 已有"哪些 profile 算数"的名单 |
| `scheduler/scheduler.mbt:121` | multi_node 时**只做拒绝**：profile 缺失或不在名单里就 `RuntimeUnsupported` |
| `deployment/planner.mbt:109` | **无条件拒绝** `supports_multi_node` 的运行时模板 |
| `node/runtime_supervisor.mbt` | 一个 assignment 一个容器，没有 rank / 对端概念 |

也就是说：现在既不能选出一对节点，也不能把两个容器组成一次 TP。

## 3. 关键落点：CX7 关系放在 `labels` 里，不动契约

`contracts.NodeInventory` 已经有 `labels : Map[String, String]`。节点 agent（或 enrollment）
发布**互相指认**的一条标签即可：

```
spark-25e2-3d35c8fd  labels["lunanexa.io/cx7-peer"] = "spark-3782-feee26eb"
spark-3782-feee26eb  labels["lunanexa.io/cx7-peer"] = "spark-25e2-3d35c8fd"
```

由此得到本设计的核心定义：

> **validated CX7 pair** = 两台节点，`labels["lunanexa.io/cx7-peer"]` 互相指向对方，
> 且两台都可调度、架构一致。

这条定义的好处是它**可验证**（互相指认，单向声明不算），而且**对端必须在场**
（对端离线时这一对自动不成立，不会把 TP 的一半调度出去）。

新增契约常量（`contracts/types.mbt`）：

```
pub let cx7_pair_topology_profile : String = "cx7-pair-v1"
pub let cx7_pair_member_count : Int = 2
pub let cx7_peer_label : String = "lunanexa.io/cx7-peer"
```

## 4. 需要改的地方（按依赖顺序）

1. **`scheduler`：选对而不是打分**
   新增 `pub fn validated_cx7_pair(requirements, policy, members) -> Array[String] raise`：
   - `policy.validated_topology_profiles` 不含 `cx7-pair-v1` → `ProfileNotValidated`；
   - 可调度集合里凑不出**互相指认**的一对 → `NoValidatedPair`；
   - 超过一对候选 → 按现有 `score_node` 取最优一对（**不是**取前二名节点）；
   - 任何 ≥3 台的请求方式都不存在对应 profile → 天然拒绝。
   同时把 `scheduler.mbt:121` 那段"只拒绝"的检查换成调用它。

2. **`deployment/planner.mbt:109`：把无条件拒绝换成有条件放行**
   `supports_multi_node` 的模板**仅当** intent 明确指定 `cx7-pair-v1` 时合法；否则维持拒绝。
   计划产物从"一个 replica"变成"一对 replica"：`PlannedReplica` 增加 `group_id` 与 `rank`。

3. **`contracts.DesiredAssignment`：让两个 assignment 知道自己是一对**
   加 `group_id : String`、`rank : Int`、`world_size : Int`、`peer_endpoint : String`。
   这是**契约变更**，需要同步 contract fixtures 与 `COMPATIBILITY.md`。

4. **`node/runtime_supervisor.mbt`：把 rank 和互联交给容器**
   - 环境变量：`--node-rank <rank>`、`--dist-init-addr <peer>:<port>`、`NCCL_IB_HCA`、
     `NCCL_IB_MERGE_NICS=1`、`NCCL_SOCKET_IFNAME`、`TP_SOCKET_IFNAME`、
     `NCCL_CUMEM_ENABLE=0`、`NCCL_NVLS_ENABLE=0`（取值来自 GLM-5.3 EXL3 配方实测）；
   - 设备与权限：`--device /dev/infiniband --ulimit memlock=-1:-1 --cap-add IPC_LOCK`；
   - 网络：TP 需要两机直连可达，现有 `--network lunanexa-runtime` 是每节点本地的，
     必须换成能跨 CX7 直连的形态（这一步要单独设计，不能顺手改，见第 6 节）；
   - **启动顺序**：rank1 先起、rank0 后起（rank0 提供 HTTP），
     需要一次对内的协调，否则 rank0 会等超时。

5. **控制器：一对要么都在，要么都不在**
   `controller/recovery.mbt` 的重启对账要按 `group_id` 整体判定：只起来一半的 TP
   不能算 Ready，也不能只回收一半。

## 5. 需要新增的测试

- `validated_cx7_pair`：互相指认 → 通过；单向指认 → 拒绝；对端离线 → 拒绝；
  候选集里没有对 → 拒绝；policy 名单缺 `cx7-pair-v1` → 拒绝；
  三个可调度节点 → 仍然只返回一对（**永远不可能返回 3 个**）。
- planner：`supports_multi_node` + 未指定 profile → 仍然拒绝（保持现状语义）；
  指定 `cx7-pair-v1` → 产生**两个** rank 正确的 replica，且 `group_id` 相同。
- supervisor：rank 环境变量与 IB 设备参数出现在 podman 命令行里。
- 重启对账：一对里少一个 → 该组不 Ready。

## 6. 必须先想清楚的一件事：跨节点网络

现有 node agent 用 `podman run --network lunanexa-runtime`（每节点本地的 podman 网络），
容器之间不跨机。而 TP=2 要求两个容器**直接**在 CX7 上互相通信。可选做法：

- **(a) 容器直接用 host 网络 + 指定 CX7 网卡**：最接近配方（配方就是这么跑的），
  代价是容器不再网络隔离，需要重新论证 `network.allowed_egress` 那套策略；
- **(b) 在宿主机上建一条跨 CX7 的点对点链路，容器共享它**：保留隔离，但要在节点上
  维护桥/路由，属于 agent 的宿主面职责；
- **(c) 走 RDMA 直通**（`/dev/infiniband` + host 网络），实际上是 (a) 的子集。

建议先按 (a) 打通并如实记录它对现有网络策略的影响，再评估 (b)。**这一步不做完，
前四步的产物也无法真正拉起一次 TP=2。**

## 7. 与"任意双机/多机"的边界

- 没有 `cx7-pair-v1` 以外的多机 profile，新增 profile 等于新增一种被承认的硬件形态，
  必须走同样的验证（互相指认 + 对端在场 + 可调度）。
- `cx7_pair_member_count` 固定为 2；任何把 world_size 调到 3 的路径都应被
  `validated_cx7_pair` 拒绝，并有测试钉住。
