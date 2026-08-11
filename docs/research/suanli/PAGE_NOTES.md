# Suanli page-by-page research notes

> Snapshot: 2026-08-11. There is one source-linked note for every one of the
> 227 sitemap-discovered pages. These are compact research notes, not copies
> of Suanli's text. The decisions in [APPLICABILITY](APPLICABILITY.md) are
> authoritative; these per-page labels are an inventory-level triage.

## [文档](https://suanli.cn/docs/)

- **Section:** `docs`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 文档.

## [关于](https://suanli.cn/docs/about/)

- **Section:** `about`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 关于.

## [联系我们](https://suanli.cn/docs/about/contact/)

- **Section:** `about`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 工作时间; 技术支持; 销售咨询; 销售电话; 问题反馈.

## [（产品）云主机](https://suanli.cn/docs/cloud-hosting/)

- **Section:** `cloud-hosting`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** （产品）云主机.

## [基础镜像](https://suanli.cn/docs/cloud-hosting/base-image/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 基础镜像.

## [最佳实践](https://suanli.cn/docs/cloud-hosting/best-practice/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 最佳实践.

## [使用云主机的 Jupyter Lab 进行读取训练](https://suanli.cn/docs/cloud-hosting/best-practice/ar56w3rlgia4t3ksohxc7wzhnif/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 使用云主机的 Jupyter Lab 进行读取训练.

## [「提示词反推工具」：图像打标批处理/炼丹必备辅助神器](https://suanli.cn/docs/cloud-hosting/best-practice/eknowvcdeicw5oksqsbcn91onee/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、为什么你需要「提示词反推」？; 二、一分钟快速上手; 三、实测案例：蓝白裙萝莉复刻挑战; 四、高级玩法：自定义系统提示词.

## [通过镜像站下载模型到云主机](https://suanli.cn/docs/cloud-hosting/best-practice/gjz3wphrzih4zwkeqilc9golnfd/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 适用场景; 前置准备; 1. 启动一台云主机实例; 2. 规划模型存放目录; 3. 获取并配置 Hugging Face Token（重要）; 核心流程：下载 Z-Image-Turbo.

## [如何在 JupyterLab 快速解压文件](https://suanli.cn/docs/cloud-hosting/best-practice/guykwtn6dilqdnk8qelcstvwn0b/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 1.使用 Shell 命令 (最常用); 1.1 解压 .zip 文件; 1.2 解压 .tar.gz 或 .tgz 文件; 1.3 解压 .tar.bz2 或 .tbz2 文件; 1.4 解压 .tar 文件 (无压缩); 2.使用 Python 标准库 (更具编程性).

## [在共绩算力使用 OpenClaw 社区镜像完整指南](https://suanli.cn/docs/cloud-hosting/best-practice/h6a2wnfquivhk1kkagkcywj4ndf/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 第一步：登录并检查状态; 第二步：触发配置向导 (关键); 第三步：启动网关服务 (解决 Host 限制); 第四步：获取最新 Token; 第五步：本地连接 (SSH 隧道); 💡 常见问题：如果 openclaw configure 没反应？.

## [云主机最佳实践](https://suanli.cn/docs/cloud-hosting/best-practice/ibntwos1pipmmdkltgqcuizsngc/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 数据安全必读; 一、快速快速上手总览; 二、创建云主机（Step 1）; 2.1 进入云主机控制台; 2.2 GPU 设备选择逻辑（简化决策模型）; 显存层面.

## [如何优化云主机共享内存](https://suanli.cn/docs/cloud-hosting/best-practice/ijubw8vdoigr40k9b4lcjx9cnce/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1. 问题描述; 1.1 典型错误信息; 1.2 问题场景; 1.3 根本原因分析; 2. 解决方案; 2.1 立即修复（推荐）.

## [如何在云主机中保存应用数据](https://suanli.cn/docs/cloud-hosting/best-practice/k6bcwuuhaiudqykruwtcdal6nxb/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1.确认自己需要共享的存储卷; 2.创建云主机时选择存储桶挂载到指定目录下; 3.上传文件，多机共享; 3.1 上传文件; 3.2 换区访问数据.

## [怎么用云主机配置 生图模型 环境并使用自动弹性扩缩容](https://suanli.cn/docs/cloud-hosting/best-practice/lsbawnbdrill6wkfiiycipwgnqg/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1.背景目标; 2.准备工作; 3.模型调用; 4.基于 gradio 的界面构建; 5.非平台基础镜像如何配置 SSH 连接; 6.如何转换为弹性部署服务（自动弹性扩缩容）.

## [使用教程——Vscode](https://suanli.cn/docs/cloud-hosting/best-practice/mhrww40deikwmwk5jzxcwxg4nvg/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 1.启动界面：; 2.编辑页面; 2.1 活动栏与侧边栏; 2.2 编辑区; 2.3 状态栏.

## [使用教程——JupyterLab](https://suanli.cn/docs/cloud-hosting/best-practice/mpefwypdjip0gmkqymecilhhnsd/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 基本功能介绍.

## [基于 ComfyUI 的社区镜像二次创作流程](https://suanli.cn/docs/cloud-hosting/best-practice/pakawqlbvimgvzkbd0hcrrk5nrg/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 一、从云主机 ComfyUI 基础镜像扩展工作流（推荐方式）; 1. 环境准备; 2. 下载缺失节点; 3. 补全模型与配置文件; 3.1 通过官方的模型管理器下载补充模型; 3.2 外部下载 &#x26; 导入模型.

## [怎么用云主机配置 LLM 环境并使用自动弹性扩缩容](https://suanli.cn/docs/cloud-hosting/best-practice/qwftwzrm1iaqphkjnmacsqqunpg/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1.背景目标; 2.准备工作; 3.下载 Qwen-7B-Chat 模型; 3.1 终端下载模型; 3.2 python 代码 下载模型; 3.3 验证模型完整性.

## [云主机如何设置开机自启动程序](https://suanli.cn/docs/cloud-hosting/best-practice/rajlwzhqaiwcaykuxvbcafgjn0k/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 为什么推荐这种方式？; 核心操作步骤; 1. 在控制台进入启动命令配置; 2. 填写配置块; 3. 保存并应用; 常见场景配置示例.

## [Vscode 通过 Remote ssh 连接云主机](https://suanli.cn/docs/cloud-hosting/best-practice/rwrkwy8noi2f7skdqtyc8ojvnzd/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 适用场景; 操作系统设置; 云主机设置; Vscode 设置.

## [社区镜像创作上传流程指引](https://suanli.cn/docs/cloud-hosting/best-practice/suwcwwbsvisaftkkr4jcwxbdn3f/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 1.云主机操作流程指引; 1.1 官网地址： https://www.gongjiyun.com/; 1.2 云主机产品操作流程; 1.3 选择基础镜像或者 ComfyUI 基础镜像; 2.发布为一个新的镜像; 2.1 当您二次开发完之后通过设备管理中 部署服务 发布您的镜像便于社区其他用户使用.

## [通过镜像站下载插件并编译](https://suanli.cn/docs/cloud-hosting/best-practice/uv0cwgo2siwwbpkmg9tc7x8tnmg/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 适用场景; 前置准备; 启动带 CUDA 环境的云主机实例; 规划插件源码与编译目录; 配置 GitHub Personal Access Token（按需）; 核心流程：下载并编译 flash-attention.

## [如何在自己的镜像中配置 SSH](https://suanli.cn/docs/cloud-hosting/best-practice/vkqcwyjz8i8yksknot6cia2fn0e/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 1. 基础镜像与自定义镜像的 SSH 配置差异; 2. 通过命令行终端直接配置 SSH 服务; 2.1 访问命令行终端; 2.2 在运行中的容器内安装 SSH 服务; 2.3 通过命令行配置密码登录; 2.4 通过命令行配置免密登录.

## [守护进程（开后台）](https://suanli.cn/docs/cloud-hosting/best-practice/wyp7wfifcixzwfkhfkdc4mlxnrq/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 一、使用 JupyterLab 终端执行程序; 二、使用 screen 工具管理会话; 安装 screen：; 创建新会话：; 临时离开当前会话：; 重新接入原有会话：.

## [如何在云主机上快速开始机器学习训练](https://suanli.cn/docs/cloud-hosting/best-practice/x8qewnzigiodzfkgllecmkwanxl/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1 用基础镜像创建云主机; 1.1 第一步：创建云主机; 1.2 第二步：配置资源; 1.2.1 设置实例名称; 1.2.2 选择基础镜像; 1.2.3 开通共享存储卷服务，挂载到本机目录（实现多机训练数据共享）.

## [常见问题](https://suanli.cn/docs/cloud-hosting/faq/)

- **Section:** `cloud-hosting`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 常见问题.

## [云主机常见问题](https://suanli.cn/docs/cloud-hosting/faq/vwuvwbms2ipchlkzyftcrgwlnmd/)

- **Section:** `cloud-hosting`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 平台使用; 如何计费; 什么是云主机？; 云主机的主要功能特点; 关机、关机并保存镜像、强制关机的区别是什么？; 1. 普通关机.

## [使用说明](https://suanli.cn/docs/cloud-hosting/function-usage-instructions/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 使用说明.

## [如何使用 SSH 连接云主机](https://suanli.cn/docs/cloud-hosting/function-usage-instructions/aanqw1zk3iedntkvqc6c6aapnkk/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 1.图形工具; 2.SSH 代理命令; 2.1 代理云服务器中的端口到本地; 2.2 代理本地端口到云服务器; 3.常见错误.

## [云主机启动命令配置规范](https://suanli.cn/docs/cloud-hosting/function-usage-instructions/c107wvm6eizpkvkhoxvcrmhtnjs/)

- **Section:** `cloud-hosting`
- **Assessment:** **Reject for managed mode** — Conflicts with managed-node security; it is permissible only inside a separately governed exclusive-node lease where the lease contract allows it.
- **Topic outline:** 1. 核心概念; 1.1 配置示例场景; 2. 常见问题分类; 3. 错误案例与解决方案; 3.1 引号与转义问题; 3.2 空格缺失问题.

## [云主机服务转弹性部署服务](https://suanli.cn/docs/cloud-hosting/function-usage-instructions/ea6mwbcemi6b6mkulagcxvvynkc/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、进入部署入口; 二、关机并保存镜像; 三、选择部署配置; 四、配置启动命令; 五、配置运行命令与运行参数; 运行命令.

## [如何使用基础镜像/通过基础镜像保存的镜像](https://suanli.cn/docs/cloud-hosting/function-usage-instructions/taaewpcy3ierj6km0okcmr40nuc/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1.当我们 使用基础镜像/通过基础镜像保存的镜像 选择 部署服务 时; 2.先进行关机并保存镜像，设置好镜像标签，方便一会选择; 3.选择配置; 4.配置启动命令; 5.配置运行命令和运行参数; 6.创建弹性部署服务.

## [云主机如何设置端口信息](https://suanli.cn/docs/cloud-hosting/function-usage-instructions/vyvhwddfkixca2km5vxckeeknab/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1. 快捷访问（HTTP 端口暴露）; 1.1 默认快捷访问端口; 1.2 自定义添加端口; 2. SSH 登录配置; 2.1 获取 SSH 登录信息; 2.2 SSH 登录注意事项.

## [云主机中使用共享存储卷](https://suanli.cn/docs/cloud-hosting/function-usage-instructions/yvawwrzvcivbypk8vihcgjrkn8c/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、产品概述; 核心特性; 二、使用指南; 1. 创建存储桶; 2. 查看连接的云主机; 3. 修改存储桶.

## [产品计费](https://suanli.cn/docs/cloud-hosting/product-billing/)

- **Section:** `cloud-hosting`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 产品计费.

## [云主机服务计费说明](https://suanli.cn/docs/cloud-hosting/product-billing/zbytw9t7ri410jkfacyccav2nfd/)

- **Section:** `cloud-hosting`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 云主机计费基本规则; 计费开始时间&#x26;计费结束时间; 扣费时机; Q：镜像拉取过程收费吗？; Q：关机过程中，收费吗？; Q：关机后，还收费吗？.

## [产品简介](https://suanli.cn/docs/cloud-hosting/product-brief-introduction/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 产品简介.

## [功能概览](https://suanli.cn/docs/cloud-hosting/product-brief-introduction/dshpwrplciaypvks63bcedlnnbh/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、计算资源管理; 1. GPU 独占功能; 二、存储与数据访问; 1. 对象存储加速挂载; 2. 共享存储卷挂载; 三、镜像与环境管理.

## [产品优势](https://suanli.cn/docs/cloud-hosting/product-brief-introduction/igj6wcff5iji1pk51pyciguhnzc/)

- **Section:** `cloud-hosting`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、算力资源优势; 1. GPU 资源丰富度; 2. 极致性能体验; 二、开发效率优势; 1. 完整工具链预装; 2. 镜像与版本管理.

## [应用场景](https://suanli.cn/docs/cloud-hosting/product-brief-introduction/quj1w1b77imeznkepwmc4nscngc/)

- **Section:** `cloud-hosting`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、AI 模型开发与训练; 核心场景; 价值体现; 二、算法竞赛与科研实验; 核心场景; 价值体现.

## [什么是云主机](https://suanli.cn/docs/cloud-hosting/product-brief-introduction/tzizwto92i0i1ukexkncwjt3nmh/)

- **Section:** `cloud-hosting`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 产品概述; 技术特性 &#x26; 核心优势; 丰富的 GPU 资源; 极速启动与高性能环境; 完整开发工具链; 灵活计费与高效资源调度.

## [快速入门](https://suanli.cn/docs/cloud-hosting/quickstart/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 快速入门.

## [快速上手云主机服务](https://suanli.cn/docs/cloud-hosting/quickstart/rtsfwxqkiiozojkcia9cxrvgntf/)

- **Section:** `cloud-hosting`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、创建云主机; 1.1 进入云主机控制台; 1.2 GPU 设备选择逻辑; 显存层面; 性价比层面; 实际选择策略.

## [（产品）DockerWeb](https://suanli.cn/docs/docker/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** （产品）DockerWeb.

## [快速上手](https://suanli.cn/docs/docker/flujwhdcti6g06kzfrvccvgbnxd/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 快速上手.

## [镜像仓库](https://suanli.cn/docs/docker/flujwhdcti6g06kzfrvccvgbnxd/harbor/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 步骤 1: 登录共绩算力镜像站; 步骤 2: 为镜像添加标签; 步骤 3: 推送镜像.

## [3 步上手](https://suanli.cn/docs/docker/flujwhdcti6g06kzfrvccvgbnxd/quick/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1 准备 compose 文件; 2 发布任务; 2.1 登录 控制台; 2.2 新建任务; 2.3 填写任务信息; 3 查看运行状态.

## [Docker Compose 指南](https://suanli.cn/docs/docker/flujwhdcti6g06kzfrvccvgbnxd/start/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 指定镜像源; 端口转发设置; 不支持 volumes; 其它配置.

## [怎么用](https://suanli.cn/docs/docker/tutorials/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 怎么用.

## [容器化部署 ComfyUI](https://suanli.cn/docs/docker/tutorials/comfyui/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 开源案例; 整体流程; 环境要求; 项目结构; 选择 Docker 基础镜像; 下载模型和扩展.

## [容器化部署 Flux.1-dev 文生图模型](https://suanli.cn/docs/docker/tutorials/sph5wenfaib0jekkq9ac57spn3f/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** （一）下载模型文件; （二）创建 Dockerfile 文件; （三）创建目录; （四）执行构建; （五）本地测试（推荐）; 获取 API 文档.

## [其它开源示例](https://suanli.cn/docs/docker/tutorials/w1j6wfv8ti6d1ekld3lc06dsnrk/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** FunASR; FFmpeg.

## [优享算力](https://suanli.cn/docs/docker/vonkw4r9iijek2khqbmcnbklnoc/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 优享算力.

## [常见问题](https://suanli.cn/docs/docker/vonkw4r9iijek2khqbmcnbklnoc/faq/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** no port available 错误; 显示 whoami 页面; proxy request failed(data) 错误; not find for domain.

## [为什么？](https://suanli.cn/docs/docker/vonkw4r9iijek2khqbmcnbklnoc/why/)

- **Section:** `docker`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 什么是共绩算力？; 什么是弹性？.

## [费用中心](https://suanli.cn/docs/expense-center/)

- **Section:** `expense-center`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 充值; 账单管理; 合同管理; 资源包管理.

## [发票管理](https://suanli.cn/docs/expense-center/apy4woyrsipziokpec2cmio7nhf/)

- **Section:** `expense-center`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 充值; 账单管理; 合同管理; 资源包管理.

## [发票功能说明](https://suanli.cn/docs/expense-center/apy4woyrsipziokpec2cmio7nhf/oguowbfw3ibocrk8i5ccbzrfn8d/)

- **Section:** `expense-center`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 开票基本规则; 开票模式说明; 自助开票操作指引; 第一步：管理发票抬头; 第二步：发起开票申请; 第三步：获取电子发票与凭证.

## [账单管理](https://suanli.cn/docs/expense-center/bill-management/)

- **Section:** `expense-center`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 充值; 账单管理; 合同管理; 资源包管理.

## [费用账单](https://suanli.cn/docs/expense-center/bill-management/tlzqwytynil7qbktxl6crn7antd/)

- **Section:** `expense-center`
- **Assessment:** **Adopt** — Directly useful as an operational or control-plane pattern, subject to LunaNexa assignment and lease fencing.
- **Topic outline:** 概述; 多维度账单视图; 账单筛查与概览功能; 服务详情深度解析; 账单导出; 充值.

## [合同管理](https://suanli.cn/docs/expense-center/contract-management/)

- **Section:** `expense-center`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 充值; 账单管理; 合同管理; 资源包管理.

## [框架合同](https://suanli.cn/docs/expense-center/contract-management/h8knwrsfrihmqokjyopcx84endg/)

- **Section:** `expense-center`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 概述; 创建框架合同; 点击创建框架合同。; 填写甲方信息; 确认合同文本; 确认签署信息.

## [发票管理](https://suanli.cn/docs/expense-center/invoice-management/)

- **Section:** `expense-center`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 充值; 账单管理; 合同管理; 资源包管理.

## [订单管理](https://suanli.cn/docs/expense-center/order-management/)

- **Section:** `expense-center`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 充值; 账单管理; 合同管理; 资源包管理.

## [资源包管理](https://suanli.cn/docs/expense-center/resource-pack-management/)

- **Section:** `expense-center`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 充值; 账单管理; 合同管理; 资源包管理.

## [预留资源包](https://suanli.cn/docs/expense-center/resource-pack-management/qqn3wbknpio3kfkpk1gcgxjmnef/)

- **Section:** `expense-center`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 概述; 核心价值; 使用场景; 计费方式; 抵扣规则; 计费规则.

## [充值](https://suanli.cn/docs/expense-center/top-up/)

- **Section:** `expense-center`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 充值; 账单管理; 合同管理; 资源包管理.

## [如何充值余额](https://suanli.cn/docs/expense-center/top-up/ykxkwsg69id70vkoceicy9nunve/)

- **Section:** `expense-center`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 打开共绩算力控制台; 进入充值页面; 选择充值金额; 选择支付方式; 完成支付; 查看充值结果.

## [（产品）弹性服务部署](https://suanli.cn/docs/flexible-deployment/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** （产品）弹性服务部署.

## [最佳实践](https://suanli.cn/docs/flexible-deployment/best-practice/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 最佳实践.

## [弹性扩缩容 - 多策略负载均衡最佳实践](https://suanli.cn/docs/flexible-deployment/best-practice/db6owixieidl3gk97nzc99tjn3d/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adopt** — Directly useful as an operational or control-plane pattern, subject to LunaNexa assignment and lease fencing.
- **Topic outline:** 适用场景; 快速上手; 1.环境准备; 2.配置文件填写; 3.部署服务; 原理.

## [通过对象存储加速持久化模型缓存](https://suanli.cn/docs/flexible-deployment/best-practice/exajwjyefiqkk0k2t0hcorz7ndh/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adopt** — Directly useful as an operational or control-plane pattern, subject to LunaNexa assignment and lease fencing.
- **Topic outline:** 1. 场景; 2. 重要说明; 3. 使用前提; 4. 整体操作流程; 5. 确认模型目录; 6. 准备对象存储中的模型文件.

## [通过 API 实现弹性节点扩缩容](https://suanli.cn/docs/flexible-deployment/best-practice/hluuwbakeiyzsnkjan4cmynkngo/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1.任务节点数量修改接口; 1.1 请求参数; 1.2 请求体示例; 1.3 调用示例代码 (Python); 1.4 返回响应; 1.5 完整调用示例与成功响应.

## [弹性部署服务最佳实践](https://suanli.cn/docs/flexible-deployment/best-practice/ksv1wr3mgiz2c9ki7tccqpmfnae/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一。环境准备; 1. 本地环境将服务容器化; 2. 注册并初始化账号，申请测试券; 2.1. 设置登陆密码并绑定微信（可选）; 2.2. 激活账号; 2.3. 申请测试算力券.

## [日志采集容器配置说明](https://suanli.cn/docs/flexible-deployment/best-practice/mtz0wueb8i6407kj4gwcejgennd/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、功能入口; 二、日志容器配置指引; 云服务商选择与鉴权配置; 日志源配置; 日志轮转托管; 三、 ⚠️ Job 批处理任务专属退出机制.

## [通过共享存储卷持久化模型缓存](https://suanli.cn/docs/flexible-deployment/best-practice/nhlwwdnfwidouokwm4zco5yrnha/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adopt** — Directly useful as an operational or control-plane pattern, subject to LunaNexa assignment and lease fencing.
- **Topic outline:** 场景; 共享存储卷介绍; 1.确认缓存目录; 2.新建共享存储卷; 3.挂载到业务容器; 4.效果验证.

## [如何发布 Job 任务类型](https://suanli.cn/docs/flexible-deployment/best-practice/pdyiwcb3die8jqkzvhdclrxfnsf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1 Job 任务类型; 2 通过弹性部署发布; 3 通过 API 形式发布 Job 任务类型; 3.1 接口概述; 3.2 Job 任务配置示例; 4.改参 - 提交 - 看状态 - 进终端.

## [任务创建接口与多容器部署指南](https://suanli.cn/docs/flexible-deployment/best-practice/rjzowsroki7ckdkzfllceoc5nnf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1 任务创建接口; 1.1 接口概述; 1.2 多任务类型支持; 2 配置示例; 2.1 Job 任务示例; 2.2 多容器 Deployment 任务示例.

## [弹性部署服务推理性能调优](https://suanli.cn/docs/flexible-deployment/best-practice/tibmwbgh0i520mk8esjcdkjgnzd/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1. 检查 GPU 是否实际被使用; 1.1 验证 GPU 可用性; 1.2 在代码中验证 GPU 使用; 1.3 运行时 GPU 使用监控; 2. 尝试更换高性能 GPU，确认性能瓶颈是否与 GPU 硬件相关; 2.1 GPU 性能对比测试.

## [弹性扩缩容-FIFO 队列最佳实践](https://suanli.cn/docs/flexible-deployment/best-practice/xtizw18ejibryhkdvc6cfdinnwf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adopt** — Directly useful as an operational or control-plane pattern, subject to LunaNexa assignment and lease fencing.
- **Topic outline:** 适用场景; 快速上手; 1.环境准备; 2.配置文件填写; 3.部署服务; 原理.

## [常见问题](https://suanli.cn/docs/flexible-deployment/faq/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 常见问题.

## [弹性部署常见问题](https://suanli.cn/docs/flexible-deployment/faq/hsxowl4y2i5eogkdsnvcuhv0nae/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 平台使用; 怎么计费的？; 如何实现弹性扩缩容？; 什么是 Serverless 与无状态？为什么不提供 SSH？; 弹性部署与其他平台的容器实例（或虚拟机）有什么区别？; 部署阶段.

## [使用说明](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 使用说明.

## [跨区域调度功能说明](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/bhwuwxdn2iws3dkx2bccla0aneh/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、功能概述; 二、适用场景; 三、功能限制说明; 四、演示流程; 五、注意事项.

## [镜像预热功能说明](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/caslwb4whih2h8kump9cmrspnyg/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adopt** — Directly useful as an operational or control-plane pattern, subject to LunaNexa assignment and lease fencing.
- **Topic outline:** 一、概述; 二、适用场景; 三、功能限制; 四、演示流程; 1、在弹性部署服务页面新增镜像预热功能。; 2、镜像预热任务进行.

## [创建多容器部署任务功能说明](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/ivnkwepb7ixtwiknmazc5prunmf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、概述; 二、适用场景; 三、演示流程.

## [如何使用自动弹性扩缩容](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/jurlwpstdiyokzkzwqocfpclnbf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1. 功能概述; 2. 功能优势; 3. 使用流程; 3.1 参数设置建议; 3.2 创建任务时配置; 3.3 任务运行中调整.

## [资源监控功能说明](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/mgywwvml7ionb1ksgpdcimvmn9e/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adopt** — Directly useful as an operational or control-plane pattern, subject to LunaNexa assignment and lease fencing.
- **Topic outline:** 概述; 适用场景; 演示流程.

## [预留资源包](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/qqn3wbknpio3kfkpk1gcgxjmnef/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 概述; 核心价值; 使用场景; 生命周期; 计费方式; 抵扣规则.

## [健康检测](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/qxsswhtpfifsuskfwxgcwbstnwb/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adopt** — Directly useful as an operational or control-plane pattern, subject to LunaNexa assignment and lease fencing.
- **Topic outline:** 1.概念定位; 1.1 存活探针; 1.2 就绪探针; 1.3 启动探针; 2.平台视角下的探针实际案例; 2.1 启动探针检测容器中的应用是否已经启动.

## [镜像仓库使用指南](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/rkicwd7zqi39lmkti9gc5pcungb/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1. 服务选择建议; 2. 镜像仓库 使用指南; 2.1 步骤 1: 登录共绩算力镜像站; 2.1.1 Windows 系统操作步骤; 2.1.2 Mac 系统操作步骤; 2.1.3 密码重置指引.

## [对象存储加速](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/wqhqwbcf3i6byykijbvct9dkn0e/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1. 功能简介; 2. 操作流程; 2.1. 对象存储加速; 2.2. 获取对象存储配置; 2.2.1. 权限说明; 2.2.2. 阿里云 OSS.

## [K8S YAML 导入](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/zql7wksxvios4rk0uotcidkfn25/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reject** — Conflicts with LunaNexa's managed-node security and typed deployment invariants.
- **Topic outline:** 发布 Job 任务; 发布多容器 Pod; 实现容器内业务的优雅退出; 自定义 yaml 增加环境变量和启动命令等信息; 解决容器内无法访问外部四层服务的问题; 服务零中断滚动更新.

## [预制服务](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 预制服务.

## [容器化部署 JupyterLab](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/arpnwf5t4ikq17k7cpwc1axlnnb/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1.在 共绩算力 上运行 JupyterLab; 1.1 选择 GPU 型号; 1.2 选择服务配置; 1.3 部署; 2.自定义与扩展：利用 Docker Hub 资源优化您的 JupyterLab 镜像; 3.JupyterLab 数据持久化容器镜像的构建.

## [容器化部署 Ollama+Qwen3+Open WebUI](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/baarw4prxixl6jktng7chjktnwe/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1、部署服务; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击【新增部署任务】。; 1.2 选择设备; 1.3 选择相应预制镜像; 1.4 耐心等待节点拉取镜像并启动; 1.5 部署完成.

## [容器化部署 ComfyUI-ReActor 并通过 api 调用](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/bv6dwthf5ispsjkyfnicmepwn1f/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 部署流程; 验证部署; 通过 api 调用服务：; Step 1: 编码图片; Step 2: 合并成 comfyui 工作流; Step 3: 发送请求.

## [容器化部署 DailyHot](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/bxgbwq5w4igq2qkg1kuce4j8neb/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1.在共绩算力上运行 DailyHot; 1.1 创建部署服务; 1.2 选择 GPU 型号; 1.3 选择预制镜像; 1.4 部署并访问服务; 2.快速上手.

## [容器化部署 CosyVoice](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/ehh3wzfijipwrckp1kpchuzbnqh/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1.在共绩算力上运行 CosyVoice; 1.1 创建部署服务; 1.2 选择 GPU 型号; 1.3 选择预制镜像; 1.4 部署并访问服务; 2.快速上手.

## [容器化部署 Qwen-Image-Edit](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/etwcwf29nijubcko8hycufkvnxg/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. 访问控制台进入弹性部署界面; 2. 基于自身需要选择所需配置; 3. 选择相应服务; 4. 点击部署服务; 5. 耐心等待节点拉取镜像; 6. 节点启动后的界面.

## [容器化部署 Ollama+Qwen3](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/fsr8wbyxnitxtrka8m0cqjpfn3c/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1、部署服务; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 1.2 选择设备; 1.3 选择相应预制镜像; 1.4 耐心等待节点拉取镜像并启动; 1.5 部署完成.

## [容器化部署 Flux.1 Krea[dev]](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/geliwpy6dif5vukpvgncyne0nsc/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1 部署步骤; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 1.2 基于自身需要进行配置，参考配置为单卡 4090 和 1 个节点。; 1.3 选择相应预制镜像; 1.4 点击部署服务，耐心等待节点拉取镜像并启动。; 1.5 节点启动后，你所在“任务详情页”中看到的内容可能如下：.

## [容器化部署 PDFMathTranslate](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/gkxmwm2xaib0imktvr5crkhingb/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. 部署指南：在共绩算力上运行 PDFMathTranslate; 1.1 创建部署服务; 1.2 配置计算资源; 1.3 选择预制镜像; 1.4 部署并访问服务; 2.快速上手.

## [容器化部署 HivisionIDPhotos](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/gnfiw9tghi44hpkcetccxr0wnqh/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1.在共绩算力上运行 HivisionIDPhotos; 1.1 创建部署服务; 1.2 选择 GPU 型号; 1.3 选择预制镜像; 1.4 部署并访问服务; 2.快速上手—— 快速抠图蓝底证件照.

## [容器化部署 FramePack-F1 图生视频框架](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/h03bwgkgjifejjkwklccf6tpnmd/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1 部署步骤; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 1.2 基于自身需要进行配置，参考配置为单卡 4090 和 1 个节点（初次使用进行调试）。; 1.3 选择相应预制镜像; 1.4 点击部署服务，耐心等待节点拉取镜像并启动。; 1.5 节点启动后，你所在“任务详情页”中看到的内容可能如下：.

## [容器化部署 Z Image Turbo](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/hdwgwf9ueiri8vkhum0couxpnlg/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. 访问控制台进入弹性部署界面; 2. 基于自身需要选择所需配置; 3. 选择相应服务; 4. 点击部署服务; 5. 耐心等待节点拉取镜像; 6. 节点启动后的界面.

## [容器化部署 Qwen-Image-Layered](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/jhbuwtlsoivrsmkilqucp0uun3b/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 0.Qwen-Image-Layered 简介; 1 部署步骤; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 1.2 基于自身需要进行配置，参考配置为单卡 5090 和 1 个节点。; 1.3 选择相应预制镜像; 1.4 点击部署服务，耐心等待节点拉取镜像并启动。.

## [GPT-OSS-20B 弹性部署](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/jyrkwxxmhi1t68ktdancqk6hnfb/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 部署流程; 验证部署; 小例子 🌰：.

## [容器化部署 HunyuanWorld-Mirror Demo](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/kuxjwpidlizeqgk0ce6c6cs8nzg/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 简介; 快速部署; 快速使用.

## [容器化部署通用推理镜像 Ollama 篇](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/l5qnwltyeiumluk7hbqcucofnsr/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 快速开始; 选择模型; 配置服务; 配置推理服务; 部署服务.

## [容器化部署通用推理镜像 vLLM 篇](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/lpp2wq1gmiskmqkvf3ycpwxvnhf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 快速开始; 部署流程; 确认模型 id; 配置部署服务; 配置模型缓存（可选）; 等待服务启动.

## [容器化部署 FaceFusion 脸部融合](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/lrgcwc6wuijywzkwasychtzbnec/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 部署流程; 验证部署; 小案例 🌰：.

## [容器化部署 Qwen Image](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/m0fpwrltaixdvpki9ebcljlcnqf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. 访问控制台进入弹性部署界面; 2. 基于自身需要选择所需配置; 3. 选择相应服务; 4. 点击部署服务; 5. 耐心等待节点拉取镜像; 6. 节点启动后的界面.

## [容器化部署 acestep1.5-5Hz-lm-1.7B](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/ndoswjtzbi7xwmk7f6zc72otnte/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. 访问控制台进入弹性部署界面; 2.界面概述; 3.生成模式.

## [容器化部署 CodeFormer](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/npk7wmkvwiw0stkhqzdcppw4npf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1.在共绩算力上运行 CodeFormer; 1.1 创建部署服务; 1.2 选择 GPU 型号; 1.3 选择预制镜像; 1.4 部署并访问服务; 2. 快速上手.

## [容器化部署 Flux.2 [dev]](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/oabhwoxwlitte3kofdlcpoawnre/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. 访问控制台进入弹性部署界面; 2. 基于自身需要选择所需配置; 3. 选择相应服务; 4. 点击部署服务; 5. 耐心等待节点拉取镜像; 6. 节点启动后的界面.

## [容器化部署 PaddleOCR-VL-0.9B](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/of4gwols0irt84kc5atc7yfhnbh/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. 在共绩算力上运行 PaddleOCR-VL-0.9B; 1.1 创建部署服务; 1.2 选择 GPU 型号; 1.3 选择预制镜像; 1.4 部署并访问服务; 2.本地客户端代码.

## [容器化部署 minerU](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/phrywztvniedlkknimdcy601nld/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 更新（2025 年 9 月 26 日）; 1.在共绩算力上运行 minerU; 1.1 创建部署服务; 1.2 选择 GPU 型号; 1.3 选择预制镜像; 1.4 部署并访问服务.

## [容器化部署 LongCat-Image](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/pqpawwj2dih7uuk2ozucctukncc/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 0.LongCat-Image 简介; 1 部署步骤; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 1.2 基于自身需要进行配置，参考配置为单卡 4090 和 1 个节点（初次使用进行调试）。; 1.3 选择相应预制镜像; 1.4 点击部署服务，耐心等待节点拉取镜像并启动。.

## [容器化部署 Qwen3.5-27B](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/rbhtwlypcixunnkkvuuce7gmnpg/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. Qwen3.5-27B 4 卡部署方案; 1.1 推荐启动命令; 1.2 最佳实践; 1.3 OpenAI 兼容调用示例; 1.4 适用场景; 2. Qwen3.5-27B 8 卡部署方案.

## [IndexTTS2 弹性部署实践](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/rdaaw9nuuizgnjk6gomct5m7nmf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** IndexTTS2 概要; 快速体验; step 1 创建部署任务：; Step 2 配置服务：; Step 3 部署服务：; 快速体验.

## [容器化部署 StableDiffusion2.1-WebUI 应用](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/rllmwjekqiadi4khxftcqwzrnhc/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1 部署步骤; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 1.2 基于自身需要进行配置，参考配置为单卡 4090 和 1 个节点（初次使用进行调试）。; 1.3 选择相应预制镜像; 1.4 点击部署服务，耐心等待节点拉取镜像并启动。; 1.5 节点启动后，你所在“任务详情页”中看到的内容可能如下：.

## [容器化部署 ACE-Step](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/ruqpwt63nifwm6klfitccvmanqc/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1.在共绩算力上运行 ACE-Step; 1.1 创建部署服务; 1.2 选择 GPU 型号; 1.3 选择预制镜像; 1.4 部署并访问服务; 2.快速上手.

## [容器化部署 Whisper](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/sjgkwdocbijmrlkppnkc9foxndb/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. 部署步骤; 1.1 访问共绩算力控制台; 1.2 进入服务列表后点击新增部署服务按钮; 1.3 基于自身需要进行配置，参考配置为单卡 4090（初次使用进行调试）。; 1.4 选择服务配置中的预制镜像 选择我们打包好的 Whisper 镜像快速开启服务; 1.5 点击部署服务，耐心等待节点拉取镜像并启动 第一次访问会下载模型，所以需要稍等一会.

## [容器化部署 FunASR](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/u2f3wvacwiqxdgk1vpqc1ptdnpe/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. 服务简介与应用场景; 1.1 典型应用场景; 2. 部署与接入; 2.1 共绩算力平台部署步骤; 3. API 协议与参数; 3.1 通信协议.

## [容器化部署 WAN2.2 5B 模型](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/vndvwtwy6ihh2skqz7vcsmxrnsy/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1 部署步骤; 1.1 访问共绩算力控制台 https://console.suanli.cn ，点击新增部署。; 1.2 基于自身需要进行配置，参考配置为单卡 4090 和 1 个节点（初次使用进行调试）。; 1.3 选择相应预制镜像; 1.4 点击部署服务，耐心等待节点拉取镜像并启动。; 1.5 节点启动后，你所在“任务详情页”中看到的内容可能如下：.

## [容器化部署 Flux.1 Kontext Dev 图片编辑模型应用](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/vsy1wrm8nizlsvkqwjucvjapn2b/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1 部署步骤; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 1.2 基于自身需要进行配置，参考配置为单卡 4090 和 1 个节点（初次使用进行调试）。; 1.3 选择相应预制镜像; 1.4 点击部署服务，耐心等待节点拉取镜像并启动。; 1.5 节点启动后，你所在“任务详情页”中看到的内容可能如下：.

## [容器化部署 HunyuanPortrait](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/wwy8wp8w6i3obkkvwolc5gzbntd/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1.在共绩算力上运行 HunyuanPortrait; 1.1 创建部署服务; 1.2 选择 GPU 型号; 1.3 选择预制镜像; 1.4 部署并访问服务; 2. 快速上手.

## [容器化部署 minicpm4](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/xdpswcng2ilsbtkgbzwcrejlnia/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1.部署服务; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 1.2 选择设备; 1.3 选择相应预制镜像; 1.4 耐心等待节点拉取镜像并启动; 1.5 部署完成.

## [容器化部署 Z Image](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/xsafwp2fkiysw3kygxzct3f4nwd/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1. 访问控制台进入弹性部署界面; 2. 基于自身需要选择所需配置; 3. 选择相应服务; 4. 点击部署服务; 5. 耐心等待节点拉取镜像; 6. 节点启动后的界面.

## [容器化部署 StableDiffusion-3.5-large 文生图模型应用](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/y0qjw1tg3iddv8k3gqkctc1xn4d/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1 部署步骤; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 1.2 基于自身需要进行配置，参考配置为单卡 4090 和 1 个节点（初次使用进行调试）。; 1.3 选择相应预制镜像; 1.4 点击部署服务，耐心等待节点拉取镜像并启动。; 1.5 节点启动后，你所在“任务详情页”中看到的内容可能如下：.

## [容器化部署 Qwen3-8B-VL](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/ycggwebvtiknjgkkrhyc0qpmn3c/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** API 配置信息; 完整代码实现; 使用指南; 1. 环境准备; 2. 基本使用; 3. 图像分析.

## [容器化部署 StableDiffusion1.5-WebUI 应用](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/yjqiw6trbihsw9klma1co5monpf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1 部署步骤; 1.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 1.2 基于自身需要进行配置，参考配置为单卡 4090 和 1 个节点（初次使用进行调试）。; 1.3 选择相应预制镜像; 1.4 点击部署服务，耐心等待节点拉取镜像并启动。; 1.5 节点启动后，你所在“任务详情页”中看到的内容可能如下：.

## [容器化部署 Flux.1-dev 文生图模型应用](https://suanli.cn/docs/flexible-deployment/pre-fabricated-services/ykjzwpbbmibaajkwkfpcb11jnce/)

- **Section:** `flexible-deployment`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1 开源案例; 2 部署步骤; 2.1 访问共绩算力控制台 https://console.suanli.cn，点击新增部署。; 2.2 基于自身需要进行配置，参考配置为单卡 4090 和 1 个节点（初次使用进行调试）。; 2.3 选择相应预制镜像; 2.4 点击部署服务，耐心等待节点拉取镜像并启动。.

## [快速入门](https://suanli.cn/docs/flexible-deployment/product-billing/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 快速入门.

## [快速上手弹性部署服务](https://suanli.cn/docs/flexible-deployment/product-billing/bv4gwriuoiec82kpkjccdbc0nie/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 前提条件; 概述; 方式一：使用预制镜像发布任务（推荐）; Step 1：新增部署任务; Step 2：填写任务信息; 2.1 选择计算资源.

## [弹性部署服务计费说明](https://suanli.cn/docs/flexible-deployment/product-billing/cpshwwfeeiqhtrkpyfjcpz2tnyg/)

- **Section:** `flexible-deployment`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一。计费基本规则; 计费开始时间&#x26;计费结束时间; 扣费时机; Q：镜像拉取过程收费吗？; Q：停止服务后，还收费吗？.

## [产品简介](https://suanli.cn/docs/flexible-deployment/product-brief-introduction/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 产品简介.

## [什么是弹性部署服务](https://suanli.cn/docs/flexible-deployment/product-brief-introduction/hhadwmdblixrydkrogrcwqrjnme/)

- **Section:** `flexible-deployment`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 产品概述; 技术特性; 容器化部署; 专业级硬件资源; 智能调度系统; 弹性计费.

## [应用场景](https://suanli.cn/docs/flexible-deployment/product-brief-introduction/lfgawgepjil7xektqrhci6drnrg/)

- **Section:** `flexible-deployment`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、AI 模型训练与推理场景; 二、业务负载波动明显的场景; 三、复杂应用部署场景; 四、无需运维的应用运行场景; 五、成本敏感型业务场景; 六、高可用性要求场景.

## [功能概览](https://suanli.cn/docs/flexible-deployment/product-brief-introduction/srzow8steizer5kr0ufc1ev2nag/)

- **Section:** `flexible-deployment`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、扩缩容能力; 平台支持手动调整资源规模：; 二、计算资源管理; CPU 独占功能; 共享内存; 三、存储与数据访问.

## [产品优势](https://suanli.cn/docs/flexible-deployment/product-brief-introduction/xuuqwkxyaimoqek9jyrccdr2nzf/)

- **Section:** `flexible-deployment`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、资源弹性与性能保障; 二、智能调度与资源优化; 三、成本控制优势; 四、容器化与部署效率; 五、高性能与高可用性; 六、企业级运维保障.

## [（产品）Job 批处理](https://suanli.cn/docs/job-batch-processing/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** （产品）Job 批处理.

## [最佳实践](https://suanli.cn/docs/job-batch-processing/best-practice/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 最佳实践.

## [Job 批处理最佳实践文档](https://suanli.cn/docs/job-batch-processing/best-practice/l41twwvo1ijbkjkeqricze2rnwg/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、产品概述; 二、计费模式选型; 三、创建 Job 批处理：全功能配置详解; 3.1 GPU 型号与资源选择; 3.2 存储配置：数据的高效流转; 3.3 镜像与运行环境配置.

## [通过 API 调用 Job 任务](https://suanli.cn/docs/job-batch-processing/best-practice/qdluwlsnyidkdlktujvcavmrnkd/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一 、 前置准备; 二 、 通用规范; 三 、 调用示例; 查询 job 任务列表; 获取设备资源列表; 创建指定的 job 任务.

## [队列任务/Spot 任务最佳实践](https://suanli.cn/docs/job-batch-processing/best-practice/waiuwjhtxijnu6kqsvqcrborndd/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 二、1 个 100 节点任务 vs 100 个单节点任务; 场景 A：100 个单节点任务（高并发零散任务）; 场景 B：1 个 100 节点任务（大规模分布式任务）; 三、其他业务场景的推荐配置; 场景一：海量低优计算（如：海量数据清洗、离线批量处理）; 场景二：需要稳定保障的分布式大任务（如：重要模型训练）.

## [常见问题](https://suanli.cn/docs/job-batch-processing/faq/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 常见问题.

## [使用说明](https://suanli.cn/docs/job-batch-processing/function-usage-instructions/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 使用说明.

## [日志采集容器配置说明](https://suanli.cn/docs/job-batch-processing/function-usage-instructions/n1bxw3lkuifkm9kulxtcemusnte/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、功能入口; 二、日志容器配置指引; 云服务商选择与鉴权配置; 日志源配置; 日志轮转托管; 三、 ⚠️ Job 批处理任务专属退出机制.

## [队列管理操作指南](https://suanli.cn/docs/job-batch-processing/function-usage-instructions/vzbtwhdqxicfqekfnxhcvwfjndd/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 产品概述与核心优势; 二、核心概念解析; 核心实体名词; 关键调度字段名词; 三、创建与管理队列; 新建队列.

## [产品计费](https://suanli.cn/docs/job-batch-processing/mz5ywgtgaijgdykiobwcq1glnls/)

- **Section:** `job-batch-processing`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 产品计费.

## [Job 批处理任务计费说明](https://suanli.cn/docs/job-batch-processing/mz5ywgtgaijgdykiobwcq1glnls/kva8wtoq6ief9kklttgcmwyanne/)

- **Section:** `job-batch-processing`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、计费基本规则; 二、计费开始时间 &#x26; 计费结束时间; 三、扣费时机; 四、常见问题 (FAQ).

## [快速入门](https://suanli.cn/docs/job-batch-processing/product-billing/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 快速入门.

## [快速上手 Job 批处理任务](https://suanli.cn/docs/job-batch-processing/product-billing/elnjwy2ihiqwllka70kcq8mvndc/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 前提条件; 概述; 发布任务流程; Step 1：新增 Job 批处理任务; Step 2：选择计费模式和开行; Step 3：定义容器与自定义镜像.

## [产品简介](https://suanli.cn/docs/job-batch-processing/product-brief-introduction/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 产品简介.

## [功能概览](https://suanli.cn/docs/job-batch-processing/product-brief-introduction/bgolwhqiqi95qrkelhxc1guwnsc/)

- **Section:** `job-batch-processing`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、任务并发与规模控制; 1.灵活的并行度配置; 2.节点索引模式; 二、计算资源与调度管理; 1.双轨计费与调度策略; 2.多级容错与自动熔断.

## [应用场景](https://suanli.cn/docs/job-batch-processing/product-brief-introduction/h8oewoccjiwfvzkdvoxcdnxmnoh/)

- **Section:** `job-batch-processing`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、大规模离线 AI 模型训练场景; 二、海量数据跑批与 ETL 处理场景; 三、大规模多媒体离线推理场景; 四、成本敏感的弱时效性计算场景; 五、高容错要求的复杂并行场景; 六、高密度科学计算与工业仿真场景.

## [什么是 Job 批处理](https://suanli.cn/docs/job-batch-processing/product-brief-introduction/hgnxwhnymiap9fk4zazcnnoznug/)

- **Section:** `job-batch-processing`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 产品概述; 为什么需要独立的 Job 批处理任务？; 技术特性; 术语解释.

## [产品优势](https://suanli.cn/docs/job-batch-processing/product-brief-introduction/roxbwkexmiucwskqszocbe1bnfd/)

- **Section:** `job-batch-processing`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、极致的并发规模与执行效率; 二、双轨计费与极致成本优化; 三、企业级容错与高可靠机制; 四、容器化与无缝环境迁移; 五、专业算力与海量数据处理; 六、全生命周期运维保障.

## [（产品）大模型云服务](https://suanli.cn/docs/large-model-cloud-service/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** （产品）大模型云服务.

## [最佳实践](https://suanli.cn/docs/large-model-cloud-service/best-practice/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 最佳实践.

## [使用 new-api 进行二次分发](https://suanli.cn/docs/large-model-cloud-service/best-practice/b5kcweejhih3fmkdrgjcoc3gnvk/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 安装部署 new-api; 配置渠道; 一、基本信息; 二、API 配置; 三、模型配置; 四、其他配置.

## [接入沉浸式翻译](https://suanli.cn/docs/large-model-cloud-service/best-practice/l69qwgiwqisbzgkrx3xcyzfgntf/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** API Key; 模型 id; url; 配置沉浸式翻译.

## [使用说明](https://suanli.cn/docs/large-model-cloud-service/function-usage-instructions/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 使用说明.

## [如何充值余额](https://suanli.cn/docs/large-model-cloud-service/function-usage-instructions/jdivwfphvimsk6kyd6gcdryxnxb/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 打开共绩算力控制台; 进入充值页面; 选择充值金额; 选择支付方式; 完成支付; 查看充值结果.

## [在线对话调试](https://suanli.cn/docs/large-model-cloud-service/function-usage-instructions/t8tlwljs1iiflgk281pcs71wnbh/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 打开对话面板; 选择测试模型; 选择 API 秘钥; 填写系统提示词; 按需调整高级设置; 测试回答.

## [创建 API 秘钥](https://suanli.cn/docs/large-model-cloud-service/function-usage-instructions/tcv1wzfm7iunykkvuwtcillznjg/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 打开 API 密钥页面; 新建 API Key; 得到 API Key.

## [产品计费](https://suanli.cn/docs/large-model-cloud-service/product-billing/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 产品计费.

## [产品简介](https://suanli.cn/docs/large-model-cloud-service/product-brief-introduction/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 产品简介.

## [大模型云服务简介](https://suanli.cn/docs/large-model-cloud-service/product-brief-introduction/goxzwttqnidwn2kffrhchi0znke/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 产品概述; 核心功能模块; 模型广场 (Model Square); 在线对话; API 密钥 (API Keys).

## [快速入门](https://suanli.cn/docs/large-model-cloud-service/quickstart/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 快速入门.

## [快速上手大模型云服务](https://suanli.cn/docs/large-model-cloud-service/quickstart/cqsrwzrbsim4idkkjbxcdux4nfg/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1. 平台简介; 2. 准备工作; 2.1 平台环境信息; 3. 了解模型信息; 3.1 模型标识符; 3.2 兼容性说明.

## [响应状态码列表](https://suanli.cn/docs/large-model-cloud-service/quickstart/ka7hwqd9vi3fipknzehcz9xun9l/)

- **Section:** `large-model-cloud-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 通用错误格式; HTTP 状态码完整使用清单.

## [（产品）裸金属](https://suanli.cn/docs/metal/)

- **Section:** `metal`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** （产品）裸金属.

## [裸金属短租服务](https://suanli.cn/docs/metal/introduction/)

- **Section:** `metal`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 裸金属短租服务.

## [概览](https://suanli.cn/docs/metal/introduction/f4e0wgw7kikjnkkyuodc03urnih/)

- **Section:** `metal`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 产品概述; 产品特性; 1. 高性能裸金属服务器; 2. 灵活计费方案; 3. 算力供应链优化; 4. 算力资源质检认证.

## [组网设备购买](https://suanli.cn/docs/metal/introduction/ic4ew2d7nittv9kxmi0cncbyn1c/)

- **Section:** `metal`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 1、选择设备配置; 1.1 选择计费方式; 1.2 选择地区; 1.3 单机 GPU 数量; 1.4 GPU 型号; 1.5 组网方式.

## [单机设备购买](https://suanli.cn/docs/metal/introduction/n9gwwyygfivsrlkadetcojflnfc/)

- **Section:** `metal`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 1、选择设备配置; 1.1 选择计费方式; 1.2 选择地区; 1.3 单机 GPU 数量; 1.4 GPU 型号; 1.5 组网方式.

## [其他](https://suanli.cn/docs/metal/other/)

- **Section:** `metal`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 其他.

## [裸金属短租平台服务协议](https://suanli.cn/docs/metal/other/bwzawzc8cikpejkxmlicqjkanlf/)

- **Section:** `metal`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、前言; 二、服务与费用; 2.1. 共绩将基于您所选择的裸金属设备型号及购买时长进行收费。; 2.2. 计费标准：; 2.2.1. 裸金属设备服务; 2.3. 带宽服务说明.

## [服务等级协议（SLA）及服务说明](https://suanli.cn/docs/metal/other/waytwcfhxicqopkrnhlct1ojnue/)

- **Section:** `metal`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 一、前言; 二、术语和定义; 2.1 共绩算力裸金属短租平台服务; 2.2 计费方式; 2.3 服务等级保证; 2.4 实例不可用.

## [平台通用](https://suanli.cn/docs/platform/)

- **Section:** `platform`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 平台通用.

## [常见问题](https://suanli.cn/docs/platform/faq/)

- **Section:** `platform`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 常见问题.

## [平台使用常见问题](https://suanli.cn/docs/platform/faq/rmgqwlh9giz9nfkvvimcwmi5npe/)

- **Section:** `platform`
- **Assessment:** **Reference only** — Useful for compatibility or operational research only; do not vendor the application/provider implementation as first-party LunaNexa code.
- **Topic outline:** 1.快速上手相关问题; 问题：新手用户如何快速上手平台？有操作文档吗？; 2.镜像相关问题; 问题：镜像上传和拉取过程是否收费？; 问题：镜像拉取时间很长怎么办？如何判断拉取状态？; 问题：如何制作和上传镜像？支持哪些镜像仓库？.

## [物料资源](https://suanli.cn/docs/platform/material/)

- **Section:** `platform`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 物料资源.

## [共绩科技 Logo 物料资源](https://suanli.cn/docs/platform/material/vtaowndnpi6awxkav24cjvzqnvc/)

- **Section:** `platform`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 资源下载; 图形; 图形 + 共绩算力文字; 图形 + 共绩算力白色文字; 共绩科技.

## [Open API](https://suanli.cn/docs/platform/openapi/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** Open API.

## [Open API RSA 模式使用指南](https://suanli.cn/docs/platform/openapi/m3p6whioxidzwaksughc4gfhnro/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1. 概述; 1.1 文档说明; 1.2 RSA 模式工作原理; 1.3 与 Token 模式的区别; 1.4 基础信息; 2. 快速开始.

## [Open API 使用文档](https://suanli.cn/docs/platform/openapi/zx3iwhbv1i8sxdkeiapcprxhn8d/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1. 概述; 1.1 什么是 Open API; 1.2 基础信息; 1.3 版本说明; 1.4 统一响应格式; 2. 快速开始.

## [隐私协议](https://suanli.cn/docs/platform/privacy-policy/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 隐私协议.

## [隐私协议](https://suanli.cn/docs/platform/privacy-policy/cewcwx3cwii59nk3ut0c0beenvg/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 隐私协议.

## [隐私协议](https://suanli.cn/docs/platform/privacy-policy/twpmwbmy2iiarbksnvccd35ontd/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、前言; 二、账户的注册、使用与安全; 三、我们如何收集、使用您的用户信息; 四、我们如何共享、转让、公开披露您的用户信息; 五、我们如何保护、存储您的用户信息; 六、怎样联系我们.

## [学术资源加速](https://suanli.cn/docs/platform/resource-acceleration/)

- **Section:** `platform`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 学术资源加速.

## [GitHub 加速配置指南](https://suanli.cn/docs/platform/resource-acceleration/askjwkwl5i5i8fkzkuacbdnfnig/)

- **Section:** `platform`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 支持加速的内容; 使用方法; 1. 通过 git clone 加速克隆仓库; 2. 使用 wget 或 curl 加速下载文件或压缩包; 平台演示; 云主机方式（推荐）.

## [Hugging Face 加速配置指南](https://suanli.cn/docs/platform/resource-acceleration/b8t4wbnsdieruakadxsc2mnrn2f/)

- **Section:** `platform`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 支持加速的内容; 使用方法; 1. 使用 huggingface-cli 加速下载; 安装工具; 设置镜像地址; 下载模型示例.

## [服务协议](https://suanli.cn/docs/platform/service-agreement/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 服务协议.

## [裸金属短租平台服务协议](https://suanli.cn/docs/platform/service-agreement/kudxwc6e2ifksdkblaxcgqbin9b/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、前言; 二、服务与费用; 2.1. 共绩将基于您所选择的裸金属设备型号及购买时长进行收费。; 2.2. 计费标准：; 2.2.1. 裸金属设备服务; 2.3. 带宽服务说明.

## [服务协议 V3](https://suanli.cn/docs/platform/service-agreement/lwn8wf6roieikykilircqh6nnkg/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、前言; 二、服务费用; 三、服务可用性; 四、 权利与义务; 五、 保密与知识产权; 六、 变更与解除.

## [服务等级协议（SLA）及服务说明](https://suanli.cn/docs/platform/service-agreement/m3jrwjh28izlqik59xucdjf4nhf/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、前言; 二、术语和定义; 2.1 共绩算力裸金属短租平台服务; 2.2 计费方式; 2.3 服务等级保证; 2.4 实例不可用.

## [服务协议](https://suanli.cn/docs/platform/service-agreement/mlhtwuyvlixjfykpr6fcfrexnth/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、前言; 二、服务产品、计费模式及服务可用性; 三、服务中止; 四、权利与义务; 五、第三方产品; 六、合规性承诺.

## [实名认证服务协议](https://suanli.cn/docs/platform/service-agreement/nvahwv6wai1fvtkg4c1ckgvwn8e/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、定义; 二、实名认证方式; 三、信息收集的目的与范围; 四、信息的使用与处理; 五、信息的存储与安全保护; 六、您的权利.

## [资源接入平台服务协议](https://suanli.cn/docs/platform/service-agreement/vbinw7mepifp7dk0vyfcd0bgn2d/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、前言; 二、定义; 三、服务内容; 四、收益结算; 五、双方权利与义务; 六、合规性承诺.

## [账号管理](https://suanli.cn/docs/platform/team-account/)

- **Section:** `platform`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 账号管理.

## [团队账号](https://suanli.cn/docs/platform/team-account/bpcxwi8vviqxylk677tcpfwqnkf/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1.登录后即可开始选择对应团队：; 2.可以通过控制台中点击个人设置 - 我的团队 进入团队信息后台; 3.切换 团队 添加成员.

## [实名认证](https://suanli.cn/docs/platform/team-account/eyobwhae3iwld4kbsvcczqtqndh/)

- **Section:** `platform`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 关于实名认证; 实名认证入口; 个人认证; 企业认证; 我的个人账号已经完成实名认证，加入企业团队后，启动算力实例、创建资源时依旧弹出实名认证拦截提示，无法正常操作？; 个人实名认证与企业实名认证有什么区别？.

## [产品动态](https://suanli.cn/docs/release/)

- **Section:** `release`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 更新日志; 公告.

## [公告](https://suanli.cn/docs/release/proclamation/)

- **Section:** `release`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 更新日志; 公告.

## [【升级通知】云主机和共享存储卷产品即将调整为白名单准入机制](https://suanli.cn/docs/release/proclamation/becfw49haixhrjkbamjcnatfnjf/)

- **Section:** `release`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 更新日志; 公告.

## [【账号管理】账号实名认证通知](https://suanli.cn/docs/release/proclamation/chhzwvop7isshrkpvo1c60eoncg/)

- **Section:** `release`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 更新日志; 公告.

## [【价格调整】产品价格调整及优惠方案通知](https://suanli.cn/docs/release/proclamation/l0v6wwndpiorjbktbytc7kxgnsh/)

- **Section:** `release`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 更新日志; 公告.

## [【产品变更】云主机磁盘限额功能即将上线](https://suanli.cn/docs/release/proclamation/rximwrrjkiutojksqq1cd052nyb/)

- **Section:** `release`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 变更说明; 更新日志; 公告.

## [【计费调整】存储计费调整公告](https://suanli.cn/docs/release/proclamation/w8yswdiwtioq9dkkdazcnucln6o/)

- **Section:** `release`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 更新日志; 公告.

## [更新日志](https://suanli.cn/docs/release/release-step-2/)

- **Section:** `release`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 更新日志; 公告.

## [2026 年更新日志](https://suanli.cn/docs/release/release-step-2/emacwf3ibirldskjybecfs0in33/)

- **Section:** `release`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 2026.7.16 (v2.4); ✨ 新功能; 🚀 优化与改进; 2026.7.2 (v2.3); ✨ 新功能; 🚀 优化与改进.

## [2025 年更新日志](https://suanli.cn/docs/release/release-step-2/ulbqwt3jxiklpzkhix1clvttnzc/)

- **Section:** `release`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 2025.12.18 (v1.7); ✨ 新功能; 🚀 优化与改进; 2025.09.11 (v1.6); ✨ 新功能; 🚀 优化与改进.

## [存储](https://suanli.cn/docs/storage-service/)

- **Section:** `storage-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 存储.

## [镜像仓库](https://suanli.cn/docs/storage-service/docker-image-repository/)

- **Section:** `storage-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 镜像仓库.

## [镜像仓库使用说明](https://suanli.cn/docs/storage-service/docker-image-repository/roiawxahji37obkymuvcgylanfd/)

- **Section:** `storage-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 服务选择建议; 阿里云容器镜像服务（ACR）; 共绩算力镜像仓库（平台内置仓库）; 共绩算力镜像仓库使用指南; 登录镜像仓库（凭证登录）; 操作流程说明.

## [镜像仓库计费说明](https://suanli.cn/docs/storage-service/docker-image-repository/ww23wvhfjigerxkmm9kccv4ynlb/)

- **Section:** `storage-service`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、访问入口; 二、免费算力券; 赠送规则; 使用规则; 三、计费标准.

## [对象存储加速](https://suanli.cn/docs/storage-service/object-storage-acceleration/)

- **Section:** `storage-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 对象存储加速.

## [对象存储加速使用说明](https://suanli.cn/docs/storage-service/object-storage-acceleration/nceowz55diqv9hkid8wcgkosnkg/)

- **Section:** `storage-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 1. 功能简介; 2. 操作流程; 2.1. 对象存储加速; 2.2. 获取对象存储配置; 2.2.1. 权限说明; 2.2.2. 阿里云 OSS.

## [对象存储加速计费说明](https://suanli.cn/docs/storage-service/object-storage-acceleration/pcjawciy5idpnvkiv78cdajmnpe/)

- **Section:** `storage-service`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、访问入口; 二、免费专用算力券; 赠送规则; 使用规则; 三、计费标准.

## [共享存储卷](https://suanli.cn/docs/storage-service/shared-storage-volume/)

- **Section:** `storage-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 共享存储卷.

## [共享存储卷计费说明](https://suanli.cn/docs/storage-service/shared-storage-volume/pysfwxxfqi8dpuklz1pcky4hnhh/)

- **Section:** `storage-service`
- **Assessment:** **Not applicable** — Provider-specific product, billing, legal, marketing, integration, or release material; cataloged for completeness.
- **Topic outline:** 一、访问入口; 二、免费专用算力券; 赠送规则; 计费规则; 计费标准.

## [共享存储卷使用说明](https://suanli.cn/docs/storage-service/shared-storage-volume/u5d3wiyetiazdckqxs7cvtuxndc/)

- **Section:** `storage-service`
- **Assessment:** **Adapt** — Relevant pattern, but provider-specific interfaces and public-cloud assumptions must be replaced by LunaNexa contracts and trust boundaries.
- **Topic outline:** 一、产品概述; 核心特性; 二、使用指南; 1、 创建存储桶; 2、 查看连接的云主机; 3、 修改存储桶.
