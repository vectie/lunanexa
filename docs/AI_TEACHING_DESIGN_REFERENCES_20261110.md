# AI 入门课：公开课件调研与改版依据

调研日期：2026-11-10。面向第一次系统接触 AI、观看两小时现场讲解的听众。

## 实际查看的材料

| 材料 | 查看方式 | 采用的设计思路 |
| --- | --- | --- |
| [李宏毅：生成式 AI 是什么](https://speech.ee.ntu.edu.tw/~hylee/genai/2024-spring-course-data/0223/0223_intro_gai.pdf) | 下载公开 PDF，渲染第 7、17 页；阅读其余页面结构 | 用具体输入输出和小算例引出概念；同一例子逐步展开 |
| [3Blue1Brown：Transformers](https://www.3blue1brown.com/lessons/gpt/) | 阅读课程页，并在浏览器查看预测图原图 | 把数据、模型和输出画成可辨识对象；用颜色与空间建立对应；保留对象的连续性 |
| [Jay Alammar：The Illustrated Transformer](https://jalammar.github.io/illustrated-transformer/) | 阅读图解，并查看 encoder_with_tensors_2 原图 | 先看整体，再展开内部；在前后图中保持词、向量和模块的位置关系 |
| [Transformer Explainer](https://poloclub.github.io/transformer-explainer/) | 查看交互界面及其嵌入、概率、温度说明 | 让参数控制直接改变图中的数值；把演示对象和操作放在一起 |
| [Google PAIR：What Have Language Models Learned?](https://pair.withgoogle.com/explorables/fill-in-the-blank/) | 阅读交互文章和界面说明 | 用一小处输入变化比较输出；明确控制变量。其 BERT 填空任务与自回归生成不同，课程不混用二者 |

这些是讲解和视觉结构的参考。重画本课程自己的图、代码和数据例子，
不复制上述作品的插图、角色、整页课件或文字。

## 对上一版的判断

上一版把很多概念写进相同的圆角框，然后依次显示。多数页面虽然有图，
实际仍是文字列表。模型、数据和硬件的外观太接近，动画也主要是出现
和消失，难以看见计算或工作过程。所有页面使用相同的宽松布局，缺少
输入输出、计算图、对比、数量图和应用场景之间的版式区分。

## 本轮执行

1. 保留原有 19 章与两小时顺序，重画关键对象：Token、模型层、文档、
   代码编辑器、GPU、机架、请求队列、视频时间线、蛋白质结构。
2. 文字示例展示原文和实际结果；训练用可计算的单参数例子；概率图可
   调温度并抽样；编程例子运行固定的 JavaScript 排序。
3. 对齐同一数据在各阶段的位置，使用颜色、连线和连续运动说明变化。
4. 区分演示、机制、对比、数量和系统图。减少大面积空框和重复说明。
5. 投屏界面使用纸面/深色演示板的层次，大图、清晰标注与结论；保留
   中英文讲稿、手动翻页和播放控制。

调研用于作者的设计判断，不代表这些作者审阅或认可了本课程。

## 第二轮：补足 Agent、系统与科学应用

本轮新增查看五份实际作品；另核对一份科学应用的原始说明。

| 材料 | 实际查看范围 | 应用到本课程 |
| --- | --- | --- |
| [Anthropic：Building effective agents](https://www.anthropic.com/research/building-effective-agents) | 阅读工作流、Agent 与编程例子；在浏览器查看编程 Agent 的四泳道原图 | 编程页改为项目、模型、编辑器/终端三泳道；逐条显示上下文、修改请求、运行结果和再次修改。保留自己的排序例子 |
| [Hugging Face：Continuous batching](https://huggingface.co/blog/continuous_batching) | 阅读技术推导；在浏览器查看 continuous_batching.png 的请求、缓存与计算排列 | 同一请求用相同颜色，明确区分请求身份与输出 Token 序号；用计算所得的时序图比较空等与补位 |
| [UW CSE599K：LLM Inference Serving Systems](https://courses.cs.washington.edu/courses/cse599k/24au/content/05-Serving-Systems.pdf) | 阅读 PDF；下载并渲染第 10、11 页，查看连续批处理表与调度时间线 | 保持相同请求、相同槽位与相同横轴；逐轮比较两种调度。没有将其 SLO 内容加入本入门课 |
| [Diffusion Explainer](https://poloclub.github.io/diffusion-explainer/) | 浏览器查看完整概览、文字条件、种子与步数控制；操作 timestep 滑块至 15 | 将文字条件放在去噪图中；保留紧贴对象的步骤控制。咖啡店图及噪声仍为本课原创机制示意 |
| [Brendan Bycroft：LLM Visualization](https://bbycroft.net/llm) | 浏览器查看 nano-gpt 概览、输入字母/编号与模型层级；未逐章运行其完整模型课程 | 借鉴固定对象身份和分层细讲，避免一步跳到只有术语的总图。没有引入 3D/WebGL 依赖 |
| [DeepMind：GNoME](https://deepmind.google/blog/millions-of-new-materials-discovered-with-deep-learning/) | 阅读候选预测、DFT 计算和 active learning 的原始说明；不是课件视觉评审 | 核对“预测候选—计算/实验—新观察—下一轮”的机制。本课散点、F/G 数值均为独立虚构例子，不冒充 GNoME 数据 |

### 本轮改动与计算范围

- Agent：用杭州半日安排，将天气返回值切换为下雨或晴天，下一工具在
  博物馆开放时间与公园路线之间变化。两条路径预先编写，用来解释信息
  如何影响下一步；没有运行自主规划模型。
- 固定工作流：音频、转录、摘要按固定顺序；动态选择用缺来源/缺数值
  分支说明，下一动作由模型提出。
- 改进循环：直接展示排序代码、harness 工具和训练权重各自怎样变化。
  RSI 的版本链是概念性假设，不把增加一个工具当成递归增长的实测证据。
- 多智能体：三份独立产品资料各交回容量、价格、续航，再汇总；不再只
  画 A+B+C。产品和值虚构，不是采购建议或当前报价。
- 批处理：程序计算 4 个请求，输出长度为 2、4、1、3；两个槽位，每轮
  每槽位输出一个 Token。固定批次 7 轮，连续补位 6 轮，共同输出 10 个
  Token。省略 Prefill、调度开销与不同轮次耗时，不宣称硬件加速比。
- AI4S：画候选散点、选中点、预测/观察表和新观察点，说明反馈怎样改变
  下一轮搜索；不将这些数值当作科学结论。
- 动画：编程泳道中沿调用方向移动信息信号；调度光标随实际计算轮次移动。
  有限播放、重来、逐步推进和减少动态效果设置继续适用。

对设计的取舍：参考作品的复杂公式和完整模型内部适合作为课后深读，
两小时入门投屏保留能用一个具体例子讲清楚的机制。所有新图和例子
使用自己的代码与数据，不复制来源作品的页面或图像。

## 第三轮：整套课程的因果与讲述检查

用户要求全套从头按上课方式排演，不只修几个页面。本轮补充参考：

| 材料 | 实际查看范围 | 采用的思路 |
| --- | --- | --- |
| [Distill：Attention and Augmented Recurrent Neural Networks](https://distill.pub/2016/augmented-rnns/) | 阅读加权读写与 attentional interfaces；浏览器查看对应原理图 | 明确把注意力画成数值乘权重再相加。借鉴可微加权组合的表达，不将历史 RNN 图当作现代 Transformer 的完整结构 |
| [MLU Explain：Neural Networks](https://mlu-explain.github.io/neural-networks/) | 浏览器查看计算图开场、Error 段落及其网络/散点画面 | 让预测、误差与参数更新发生在同一对象上；训练例的斜率、残差和 MSE 同步变化 |
| [Jay Alammar：Illustrated GPT-2](https://jalammar.github.io/illustrated-gpt2/) | 阅读生成与自注意力说明；浏览器查看 gpt2-simple-output-2.gif | 在生成过程中保持前文和新 Token 的身份；新增输出确实回到下一次输入 |
| [TensorFlow Playground](https://playground.tensorflow.org/) | 阅读官方网页的权重、输出与训练说明；浏览器加载未完成，未完成交互测试 | 仅作为数值与输出应同步显示的文字参考；不宣称操作了该模型 |

整套 43 张内容页都编写对应步骤的讲述与转场，存于
`docs/ai-class-storyboard.json`。每步有具体信息流、生成文本、数量变化、
曲线绘制或计算更新；播放在一页内有限执行，支持暂停与继续。
不是给同一个箭头换 43 个名字：请求流、参数更新、加权相加、KV 缓存、
数量条、间隔、去噪更新与路线有各自不同的对象和规则。

整体检查要点：前文怎样编码；下一 Token 怎样进入下一轮；LLM 预训练
例子的前文/目标错位；参数与上下文的区别；工具请求与返回的区别；
固定工作流也可以有分支；模型并行与副本的信息流不同；Prefill/Decode
复用什么；首 Token 和后续生成如何分别计时；预测和实验观察如何对应。

投屏只显示当前步骤解释，不同时放一条重复的固定结论。完整结论保留
在书页，逐步讲述、转场和补充说明保留在讲稿。此取舍给图形更大的
投屏面积，不把给作者看的安排和测试术语塞进观众页面。

完成中文、英文各 45 屏的作者排演：打开讲稿与补充说明，播放每一步，
等待完成后继续，逐屏保存截图与步骤记录，再查看十张整套缩略图。
修正了返回路径文字重叠和英文注意力表头；间隔图改为实际 101 个标记。
手动推进也能暂停、在原处继续；继续训练时说明与新的参数和误差同步。
原始记录与定向复查见 `output/ai-course3-20261110/REHEARSAL.md`。
这是作者排演，没有组织真实听众课堂，也没有把 120 分钟安排称为实测时长。
