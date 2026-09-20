# CX7 双机拓扑（唯一被承认的多机形态）

状态：**第 1 步已实现（选择侧），其余待做**。

已落地（提交 `8fa8dda`，`scheduler` 9/9 通过）：

- `contracts`：`cx7_pair_topology_profile = "cx7-pair-v1"`、`cx7_pair_member_count = 2`、
  `cx7_peer_label = "lunanexa.io/cx7-peer"`；
- `scheduler.NodeSnapshot.cx7_peer`（由 `api` 从节点上报的标签填充）；
- `scheduler.validated_cx7_pair()`：互相指认才成对，永远返回 2 个，否则
  `PairTopologyNotValidated` / `NoValidatedCx7Pair`；
- `place()`：多机请求返回 `selected_pair`，**要么是对、要么什么都不给**，不再退回单机；
  逐节点的 multi-node 拒绝已移除（否则会拒掉所有节点、让配对无从选起）；
- 六个用例钉住约束：互相指认 → 成对；单向 → 拒；对端不可调度 → 拒；
  三台互指 → **仍然只返回 2 个**；profile 未登记 → 拒；无 profile → 拒；单机不受影响。

`NodeSnapshot` 没有 labels，所以设计里"借 labels"那条在这层不成立——改成一个窄字段
`cx7_peer`，比塞一个通用 map 更诚实：只表达放置真正会依据的那一个事实。

**下一步（按此顺序，每步一次构建）**：

1. **planner 放行**：给 `ModelServiceIntent` 加 `topology_profile : String?`，删掉
   `validate_template` 里对 `supports_multi_node` 的无条件拒绝，改由"intent 是否指名
   `cx7-pair-v1`"来判定；注意这会给所有 JSON 夹具加一个字段，要一并更新。
2. **契约**：`DesiredAssignment` 加 `group_id` / `rank` / `world_size` / `peer_endpoint`，
   `validate_intent` 里 `replicas != 1` 那条要放宽（一对 = 一个逻辑实例、两个 rank）。
3. **supervisor + 控制器**：rank 环境变量与 RoCE 直通；重启对账按 `group_id` 整体判定。
4. **执行**：`desired_assignments` 为一对产生两个 assignment。

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
