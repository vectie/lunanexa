# AI 入门课：讲述线与参考资料

2026-11-16 修订。对象：第一次系统接触 AI 的听众。

## 当前课程主线

七张原始板书是主课内容来源，47 个讲解段落、186 条可辨认内容全部进入
正常章节正文，并映射到正式投屏与讲稿。取消独立的“板书展开”路线。
原来的 Token、注意力、RAG、指标、编程与科学等例子提供必要背景和验证。

全课为 24 章、46 张内容画面，正文目录有 60 个可读、可投屏的概念。
105 分钟内容中，78 分钟围绕板书主线讲解，27 分钟用于支撑例子；
另有第 50 分钟后的 10 分钟休息和最后 5 分钟讨论，共 120 分钟。
这些是讲授预算，不是实际听众计时。正文完整解释与投屏上的当前步骤分工明确，
教师使用例子讲关系，不逐字朗读书页。

顺序、章节归属和时长由 `docs/ai-integrated-course.json` 编写；新画面的
学生问题、演示和全部因果衔接由 `docs/ai-integrated-teaching.json` 编写。
`moon run scripts/build-ai-whiteboard.mbtx` 生成整套主课，再用
`scripts/sync-ai-coursebook.mbtx` 和实际审稿时间同步书页。
图和正文使用同一份数值与例子。186 条内容的书页位置和投屏位置见
[逐点对照](AI_WHITEBOARD_COVERAGE_20261114.md)。六处手写原文仍保留待核对，
不据此声称逐字转录已完全确认。

## 每页讲解稿

48 张投屏页均有独立的中文逐字稿，含开场说明、149 个动画步骤的操作与口述、
收束和下一页衔接；休息与讨论页也有引导。投屏内点击“讲稿”即可查看当前页，
“演示这一步”会恢复例子的初始数值，并显示对应动画步骤。原理、节奏和学生追问
放在下方“备课参考”中，按需展开。

[完整讲稿](AI_PAGE_SPEAKER_SCRIPT_20261116.md)可编辑，网站的“逐页讲稿”提供
48 页目录、打印版式和 Markdown 下载。正文可以直接讲，灰色操作提示不朗读。
本次完整逐字稿为中文；英文原有备课说明继续保留。

原稿按课程顺序存于 `docs/ai-speaking/` 的四个文件；总构建最后调用
`scripts/build-ai-speaker.mbtx`，校对页面 ID、步骤数及每页时间预算。
朗读量以每分钟 220 个中文字估算，演示操作、观察、提问另留时间。
这是两小时课程的备课预算，尚未进行真实听众试讲。

## 2026-11-11 的教学设计记录

以下保留上一轮 43 页支持课件的来源和设计过程；当前课程数量与编排以上节为准。

## 这次怎样讲

直接用翻译、总结和代码的输入输出开场。随后看文字表示、生成与训练，
再进入上下文、工具与循环，后半场看基础设施、应用和产业。
不做聊天式热场。每屏一个主题、一张过程或对比图、当前步骤的解释。
完整讲稿与观众页分开。中英文保持相同概念和讲述顺序。

用户明确要求移除导论中的全部 hardening。课程不放工程审查、权限、
风险清单、验收、SLO、生产就绪、平台边界声明或反复免责声明。
这些不是本次入门课的教学内容。原有平台操作章节保持原样。

## 投屏与动画

`scripts/build-ai-lecture.mbtx` 是 43 张内容页的编写源，生成
`docs-site/ai-lecture.json`。加上 10 分钟休息和 5 分钟提问共 45 屏，
讲授安排为 120 分钟。43 页的逐步讲述、因果动画和前后衔接由
`docs/ai-class-storyboard.json` 编写，生成时检查与每张图的步骤一一对应。
每屏有标题、图、当前步骤解释、中英文讲稿和时长。
这是一份讲授安排，不是实际课堂计时结果。

`docs/ai-class-rehearsal.json` 为每页补充开讲句、三个具体学生问题
（为什么、如何得到这一步、与上一页的联系）、演示停顿与可缩短的细节。
129 个问答是老师按需调用的备课材料，不要求在两小时内全部朗读。
`scripts/rehearse-ai-class.mbtx` 分别估算正常语速、较慢语速和增加六分钟
追问的节奏，逐页保留演示、思考和转场时间。假设与逐页结果见
[本轮课堂排演](../output/ai-course5-20261111/TEACHING_REHEARSAL.md)。

独立的“课程目录”按五个主题列出全部 43 个概念、时间段与要点，支持
中英文关键词搜索。阅读链接定位到书页中的图；投屏链接打开指定画面。
上课时也能打开目录跳转，关闭后留在当前画面。

本轮又按零基础听众逐页复查：术语在第一次需要时解释，先给任务与输入，
再展示操作与中间结果。完整的 43 页问题及修改见
[零基础走读记录](AI_BEGINNER_WALKTHROUGH_20261111.md)。
讲稿与书页标题、引言、图注的局部调整也由 storyboard 的双语字段编写。

教程中的“开始上课”进入同站投屏视图。“播放这一步”手动启动，播完当前
步骤就停留，不自动推进步骤或翻页。可暂停、续播、逐步推进和重来。
未讲到的对象隐藏；注意力、训练、缓存和批处理有各自的计算节奏。方向键翻页，空格推进图，
Esc 退出。讲稿按钮单独展开说明。

图使用原生 SVG / DOM，专门绘制文档、模型层、编辑器、GPU、机架、
请求队列与视频时间线。数据、模型、计算和输出使用固定语义颜色。
Token、工具返回和反馈循环在步骤之间保持对象连续。动画中的对象按
实际图中路径移动；文字逐步生成、数量条增长、参数线与残差更新。
这些过程由有限的帧动画控制，暂停时保留当前位置，继续时接着播放。

六类演示可以实际操作：温度改变归一化概率并可抽样；单参数回归更新
权重并计算均方误差；排序例子执行 JavaScript 的默认与数值比较排序；
天气结果改变下一工具；两种批处理策略按相同请求逐轮计算；交换注意力
权重，重新计算两组示意数值的加权和。
其余包括并行时间条、延迟时间线、批处理、去噪和蛋白质结构示意。
教学数据与示意标签紧邻图放置，不需要连接模型或下载模型权重。

公开课程的实际查看范围与设计取舍见
[课件设计调研](AI_TEACHING_DESIGN_REFERENCES_20261110.md)。

用户同时否定了上一版的展示效果。此次取消每页相同的
“试一试—迁移—检查点—几天后复习”模板，也不把课程安排表和术语
对照表当作开场。讲授节奏放在技术说明中，正文直接进入例子。
本次用户要求优先于 MoonBook 技能里逐页练习与复习格式的默认要求。

## 两小时讲述线

| 时间 | 讲述内容 | 对应页面 |
| --- | --- | --- |
| 00–26 | 输入输出与模型分工；Token、续写、注意力、训练与推理 | ai-start, ai-tokens, ai-next-token, ai-training-inference |
| 26–50 | 把需求说清楚，准备资料，接上工具，循环工作，再到分工和 RSI | ai-prompts, ai-context, ai-harness, ai-loops-rsi, ai-multi-agent |
| 50–60 | 休息 | — |
| 60–87 | GPU 的计算、容量、带宽；集群、Kubernetes、引擎；延迟与吞吐；Token 工厂 | ai-chips, ai-clusters-engines, ai-metrics, ai-token-factory |
| 87–108 | 排序程序、生成短片、蛋白质预测、会议纪要与日常工作 | ai-work-coding, ai-work-creation, ai-work-science, ai-work-business |
| 108–115 | 产业分工，API 与自己运行模型，LunaNexa 的位置 | ai-industry, ai-platform-place |
| 115–120 | 回到开场，交流提问 | ai-platform-place |

25 分钟简版：开场 3 分钟，模型 5 分钟，智能体 5 分钟，基础设施
5 分钟，应用与产业 5 分钟，平台 2 分钟。

## 例子和讲法

- Token：分词器拆片段，再编号。raincoat → rain / coat 是说明“词可以再拆小”的例子，实际拆分随分词器变化。
- 续写：The sky is 后的候选概率柱图；再把选中的 blue 接回下一轮。
- 训练与推理：用“件数 × 单价 = 总价”先学一个参数；预测、误差算式、线与参数同步变化，再区分改参数与使用参数。
- 提示词：从“整理记录”到提取事项、负责人和日期，给出实际表格内容。
- 上下文：指令、相关对话、文件与工具结果；RAG 是先检索再放入上下文。
- Harness：模型提出查天气，程序调用工具，把结果交回模型。
- 循环：写代码、运行、读结果、修改。改答案、改助手和改模型是不同层面的变化。
- RSI：改进能力，再用提升后的能力改进产生改进的机制；用 AlphaEvolve 引出代码搜索的具体研究例子。
- 多智能体：三个工作者分别调研产品，再由协调者合成比较；用同刻度时间条说明串行与并行。
- 芯片：权重与工作数据存入显存，数据通道对应带宽，两行点积说明独立计算可以并行。
- 集群与引擎：先定义集群/节点、服务实例与引擎；Prefill 的 A/B/C 状态先出现，再由 Decode 复用并追加 D，旧记录与新记录用颜色区分。
- 指标：先等 0.8 秒，再生成 2 秒，共 2.8 秒；101 个 Token 对应 100 个间隔。10 秒完成 20 个各 100 输出 Token 的回答，总吞吐为 200 输出 Token/秒。
- Token 工厂：把视角从单卡拉到电力、散热、网络、模型和持续运行。
- 应用：区分生成代码/执行代码；扩散图先看随机状态、单格数值更新、迭代，再解码；蛋白质用单条链表示序列与空间结构。
- 产业：谁提供计算、谁提供模型、谁把它接到工作中。
- 平台：用一条三段流程放回产业地图，接回原有平台教程。

## 参考资料

以下为内容的主要事实来源。资料用于理解概念，正文采用原创例子。
讲述不依赖最新产品排名、价格或市场份额。

| 内容 | 参考 |
| --- | --- |
| Token 与编码 | [Hugging Face Tokenizers](https://huggingface.co/learn/llm-course/chapter2/4) |
| 语言模型、训练 | [Hugging Face Transformers](https://huggingface.co/learn/llm-course/chapter1/4) |
| Attention | [Attention Is All You Need](https://arxiv.org/abs/1706.03762) |
| 后训练的具体例子 | [The Llama 3 Herd of Models](https://arxiv.org/abs/2407.21783) |
| 工作流与 agent | [Building effective agents](https://www.anthropic.com/research/building-effective-agents) |
| 上下文 | [Effective context engineering](https://www.anthropic.com/research/effective-context-engineering-for-ai-agents) |
| 多智能体 | [Multi-agent research system](https://www.anthropic.com/research/multi-agent-research-system) |
| 代码改进循环 | [AlphaEvolve](https://arxiv.org/abs/2506.13131) |
| GPU | [CUDA Programming Guide](https://docs.nvidia.com/cuda/cuda-programming-guide/index.html) |
| 专用加速器 | [TPU architecture](https://docs.cloud.google.com/tpu/docs/system-architecture-tpu-vm) |
| 集群编排 | [Kubernetes overview](https://kubernetes.io/docs/concepts/overview/) |
| 推理引擎与缓存 | [vLLM](https://docs.vllm.ai/en/latest/), [PagedAttention](https://arxiv.org/abs/2309.06180) |
| 延迟与吞吐 | [NVIDIA inference metrics](https://docs.nvidia.com/nim/benchmarking/llm/metrics) |
| AI 工厂的说法 | [NVIDIA AI factories](https://www.nvidia.com/en-us/solutions/ai-factories/) |
| 图像生成 | [Diffusers conditional generation](https://huggingface.co/docs/diffusers/using-diffusers/conditional_image_generation) |
| 蛋白质结构 | [AlphaFold](https://deepmind.google/science/alphafold/) |
| 材料探索与观察反馈 | [GNoME 原始说明](https://deepmind.google/blog/millions-of-new-materials-discovered-with-deep-learning/) |
| 产业背景 | [AI Index 2026](https://hai.stanford.edu/ai-index/2026-ai-index-report) |
| 开放权重与开源 | [Open Source AI Definition](https://opensource.org/ai/open-source-ai-definition) |
| JavaScript 排序 | [ECMAScript Array.prototype.sort](https://tc39.es/ecma262/multipage/indexed-collections.html#sec-array.prototype.sort) |
| LunaNexa | `docs/PRODUCT_CONTRACT.md`, `docs/ARCHITECTURE.md` |

## 本次记录

重写全部 19 个中英文导论页面，保留页面 ID 和原有 41 个平台章节。
对投屏视图从第 1 屏到第 45 屏逐页走读，展开讲稿、推进全部动画步骤，
检查衔接、字号与图的布局。另检查语言切换、重来、播放、暂停和深链接。
源摘要、双语结构、链接和部署记录由既有证据文件记录。
这是作者逐页排演，没有组织真实听众课堂，不把结构测试当作课堂结果。
