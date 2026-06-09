# 时序知识图谱+Agent 在根因分析（RCA）中的应用可行性分析

**分析日期**：2026-06-07  
**分析依据**：两篇核心参考文献的深度解读 + 联网检索近两年高质量文献  
**核心问题**：时序知识图谱（Temporal Knowledge Graph, TKG）+ Agent 是否可以应用于根因分析（RCA）领域？目前是否有相关研究？

---

## 一、两篇核心论文解读

### 1.1 Intent-Based Infrastructure and Service Orchestration Using Agentic-AI

| 属性 | 内容 |
|---|---|
| **作者** | Dimitrios Brodimas, Alexios Birbas, Dimitrios Kapolos, Spyros Denazis |
| **机构** | University of Patras, Greece |
| **发表** | IEEE Open Journal of the Communications Society, Vol.6, 2025（DOI 10.1109/OJCOMS.2025.3600706）|
| **领域** | 网络编排（IBN + Agentic AI）|

**核心架构**：
- 四智能体协作系统（均基于 ReAct agent pattern）：
  - **IDA (Intent Decomposition Agent)**：解析用户意图，拆解为执行计划，使用 RAG-MCP-Tool 检索历史相似请求
  - **CIA (Computational Infrastructure Agent)**：管理集群生命周期（创建/删除 K3s 集群），使用 SQLite-MCP-Tool
  - **KRA (Kubernetes Resources Agent)**：生成并执行 kubectl 命令（**唯一使用微调模型**的 agent，基于 3.5 万条 kubectl 命令数据集微调）
  - **SMA (Service Management Agent)**：部署、更新、监控应用，使用 Kubernetes/Docker/GitHub MCP-Tools
- **编排机制**：LangGraph 有向图，agent 间通过结构化的 Graph State（messages/next/rationale）通信；每个 agent 输出指定下一个应激活的 agent + 决策理由
- **关键设计**：(1) ReAct 推理循环（CoT + 工具调用）→ 结构化 Pydantic 输出 (2) 会话记忆 + 自动摘要（50% context window 触发）(3) Human-in-the-loop 安全中断点
- **效果**：显著提升复杂网络管理任务的任务完成率、响应精度与运营效率

**对本分析的启示**：该论文提供了 **agentic 编排的工程蓝图**——多智能体协作、工具调用、结构化状态传递、人在回路。其架构模式可直接迁移到 RCA 场景：将"用户意图→网络行动"替换为"故障观测→根因定位→修复动作"。

### 1.2 AetherLog: Log-based RCA by Integrating LLMs with Knowledge Graphs

| 属性 | 内容 |
|---|---|
| **作者** | Tianyu Cui, RuoWei Fu, Changchang Liu, Yuhe Ji, Wenwei Gu, Shenglin Zhang（通讯）, Yongqian Sun, Dan Pei |
| **机构** | 南开大学 / 香港中文大学 / 清华大学 |
| **发表** | ISSRE 2025（IEEE International Symposium on Software Reliability Engineering）|
| **等级** | CCF-B 类会议 |
| **代码** | github.com/ISSRE25-Submission-56/AetherLog |

**核心架构**：
- **离线流水线**（5 步建图）：
  1. LLM 实体/关系抽取（三种 prompting 策略并用：Zero-shot / Few-shot / CoT）
  2. BigLog（专为日志预训练的语言模型）嵌入实体
  3. DBSCAN 密度聚类合并语义等价的实体（消除冗余）
  4. 实体归一化（选取簇内嵌入质心作为代表实体）
  5. 冗余消减→Neo4j 图数据库持久化
- **在线流水线**（3 步推理）：
  1. LLM 日志摘要（zero-shot，压缩噪声日志为因果摘要）
  2. 实体提取 + 嵌入→Top-K（K=3）余弦相似检索 KG 节点
  3. 构建 context-enhanced prompt → LLM 推断根因（高相似度复用历史，低相似度推理新根因 + 动态 KG 扩展）

**关键实证**：
- 阿里巴巴与中国移动两个数据集的 **F1 分别达 0.93 与 0.97**，超出最佳基线 6–8%
- 核心优势：LLM 提供语义理解，KG 提供结构化因果链，协同抑制幻觉+增强可解释性

**关键局限（与本分析直接相关）**：
1. **KG 是静态的快照**——不编码"故障事件发生的先后顺序"与"事件的时间间隔"，而这些时序信息在面对复杂级联故障时至关重要（论文 Fig.1 示例中，nvme timeout 发生在 mount failed 之前，仅靠静态 KG 无法表达这个"先因后果"的时间方向）
2. **无 agent 闭环**——AetherLog 只给出根因标签，不包含"检测到异常→启动诊断→定位根因→建议修复→验证修复"的完整决策链

---

## 二、RCA 在时序维度的天然需求

故障在分布式系统中的传播具有内在的时间属性：

```
t1: nvme timeout（真实根因）
  └→ t2: block device I/O error（直接后果）
       └→ t3: mount failed（传播至上层）
            └→ t4: journal replay attempt（自动恢复动作）
                 └→ t5: watchdog crash（恢复失败）
                      └→ t6: soft lockup（系统崩溃症状）
```

在静态 KG 中，AetherLog 只能学到 "nvme timeout → I/O error → mount failed → watchdog crash → soft lockup" 这些共现关系，但不知道事件的**绝对时间点**和**时间间距**。这在以下场景中会失败：

1. **循环/重复故障**：同一组件反复故障 → 静态 KG 退化为自环，丢失"最近一次 vs 历史多次"的区分
2. **间歇性故障**：故障间歇出现、正常期间表象恢复 → 静态关系无法建模"有时成立有时不成立"的动态
3. **多根因并发**：同时发生的两个独立故障在静态 KG 中被拉入同一连通分量，实际不存在因果关系

→ **TKG（时序知识图谱）恰好是解决上述问题的自然抽象**：它不是将"关系"视为始终成立的事实，而是视为带时间戳的四元组 (s, r, o, t)，既可以建模事件的先后顺序，也可以建模关系随时间的变化。

---

## 三、已有研究：TKG + RCA 与 Agent + RCA 的交叉证据

### 3.1 TKG for RCA（已有多项高质量发表）

| 研究 | Venue | 等级 | 核心思路 |
|---|---|---|---|
| **UniDiag** (Zhang et al., 2024) | IEEE Trans. on Services Computing | CCF-A / 中科院一区 | **首个用 TKG 融合 metrics/logs/traces 的微服务故障诊断框架**。流式异常检测构建 TKG 快照，MOGE（R-GCN + GRU + 二阶池化）捕获异构结构与时间动态。GAIA benchmark 加权 F1=0.869(+0.117)，在线诊断<0.6s。支持新故障类型的持续学习。**代码与数据已开源。** |
| **DynaCausal** (Zhang et al., 2025) | arXiv:2510.22613 | 暂未确认 venue | 动态因果感知 RCA。多模态动态对齐（metrics/logs/traces）→ 动态调用图 → H-GAT 交互编码 → 时间因果解耦（TCD）+ 空间因果排序（SCO）双重损失。**AC@1=0.63，超出 SOTA 0.25–0.46。** |
| **MicroCBR** (Liu et al., 2024) | ICSOC 2024 | 暂未确认 | 基于时空故障知识图谱的案例推理，面向微服务故障排查 |
| **TA-ComplEx** (2025) | Computers & Industrial Engineering | 中科院一区 | 时序 KG 用于工业设备故障预测。LSTM 属性嵌入 + ComplEx 时间感知嵌入 → 注意力 LSTM → Extra-Tree 分类。轴承数据集 **F1=100%**。 |
| **KAIOps** (ASE 2025) | IEEE ASE 2025 Industry Showcase | CCF-A | 快手生产部署（万卡 GPU 集群）。**时间上下文编码** + KG + LLM 端到端 AIOps：检测→诊断→修复。 |
| **数据库告警推理** (2024) | IEEE Conference | 未确认 | 事件 KG + GAT + GRU 做动态模式匹配的数据库告警 RCA。MRR 81.5% |

**小结**：TKG 应用于 RCA 已有**明确的正向实证**，UniDiag（CCF-A TSC 2024）是这个方向最系统性的代表。但需注意，上述工作聚焦在**图嵌入/图神经网络**方法，尚未与 LLM/Agent 范式深度融合。

### 3.2 Agent for RCA（多智能体 RCA 已出现）

| 研究 | Venue | 等级 | 核心思路 |
|---|---|---|---|
| **mABC** (Zhang et al., 2024) | EMNLP 2024 Findings | CCF-B | 7 个专业化 agent（ReAct-based）协作做微服务 RCA，用**区块链式去中心化投票**抑制 LLM 幻觉，有界步数防死循环。在 AIOps Challenge 和 Train-Ticket 上评测 |
| **ALICE** (NeurIPS 2025 Expo) | NeurIPS 2025 | CCF-A 顶会 | 多智能体：代码上下文 Agent（构建程序依赖 KG）+ 事件诊断 Agent（实体拓扑图 + 可观测流上 RCA）。**桥接代码级分析与运行时诊断** |
| **DBAIOps** (Zhou & Sun et al., 2025) | 未确认 venue | 未确认 | LLM 增强的数据库运维系统，混合 KG + 推理 LLM，超越 SOTA 基线 |
| **Cloud-OpsBench** (2025) | 未确认 | 未确认 | 面向 agentic RCA 的大规模基准，452 个故障案例、40 种根因类型，覆盖 Kubernetes 全栈 |
| **AIOps Challenge 2025** + **UModel** (Alibaba Cloud) | 未确认 | 未确认 | 将可观测性数据从 data-centric 转向 object-centric 语义图建模，引入 U-SPL 管道式查询接口供 agent 自主探索拓扑；RCA 精度提升 8%，阿里云生产部署超一年 |

### 3.3 交叉地带：KG + LLM（Agent-ready KG）

| 研究 | Venue | 核心思路 |
|---|---|---|
| **AetherLog** (2025) | ISSRE（CCF-B）| LLM + 静态 KG，上文已详述 |
| **TAAF** (Tracing Summit 2025) | 追踪峰会 | 从内核追踪事件构建**时间索引 KG**，LLM 在 KG 上做 RCA 推理 → 人类可读解释 |
| **GraphRAG for Log Analysis** (2025) | 硕士论文（Lund/Bosch）| 从日志模板与构建信息构建 KG，利用图路径增强 LLM prompt；CMake 错误 F1 提升 58.9% |

---

## 四、可行性判断

### 4.1 "时序知识图谱+Agent"用于 RCA 是否可行？→ **高度可行，且具有充分的学术与工程基础**

理由分四个层面：

#### 层面一：TKG 的 RCA 适配性（已由 UniDiag、DynaCausal 等验证）
- 日志→结构化事实的提取路径已被 AetherLog（LLM 实体抽取 + DBSCAN 聚类 + Neo4j）、UniDiag（流式多模态 TKG 快照）分别打通
- 时间戳天然存在（每条日志都有时间戳），零额外成本即可将静态三元组升维为时序四元组
- TKG 的独特价值在于：(1) **时态约束**（A 先于 B） → 区分因果方向 (2) **消失/间歇性关系** → 不被历史共现误导 (3) **多模态时间对齐** → 日志+指标+追踪统一时基

#### 层面二：Agent 的 RCA 适配性（已由 mABC、ALICE 等验证）
- RCA 天然是多步推理任务：收集证据→生成假设→交叉验证→定位根因→建议修复→验证修复。Agent 的 ReAct 循环（Thought→Action→Observation→...）与该流程直接对齐
- 多智能体协作的设计模式（Brodimas et al. 的四 agent 模式 / mABC 的七 agent+投票模式）可处理 RCA 的子任务拆分（如：日志 agent、指标 agent、追踪 agent、拓扑 agent、修复 agent）
- Agent 的工具调用机制（MCP-Tools）可封装日志解析器、指标查询 API、追踪系统、配置管理工具，实现从分析到行动的闭环

#### 层面三：TKG + Agent 的协同增益（创新机会）
- **TKG 给 Agent 提供结构化长期记忆**：Agent 不必每次从原始日志推理，TKG 存储了历史故障的模式、传播路径、根因标注 → 类似 AetherLog 的 offset KG 但增加了时间维度
- **Agent 给 TKG 提供主动式保持**：新故障→Agent 推理根因→验证后自动写入 TKG（AetherLog 已有此思想但不完整）；Agent 还能检测 TKG 质量退化并触发重验证
- **借助 Intent-Based Agentic AI 模式**："意图" = 运维人员的自然语言查询（"为什么服务 A 响应变慢？"）→ IDA 拆解为 RCA 子步骤 → 多个专业 agent 协作执行 → SMA 式 agent 执行修复

#### 层面四：与 AetherLog 的对比——TKG+Agent 补上了 AetherLog 的两个关键短板
| AetherLog 的局限 | TKG+Agent 的方案 |
|---|---|
| 静态 KG，无时间因果方向 | TKG 四元组 (s,r,o,t) 编码事件先后与间隔 |
| 仅输出根因标签，无修复闭环 | Agent 从"检测异常→诊断→建议修复→验证修复"形成闭环 |
| 离线 KG 构建与在线推理分离 | Agent 可在诊断过程中主动查询/更新 KG |
| 无多模态融合（仅用 log） | Agent 可调用 metrics 工具、trace 工具协同推理 |
| KG 易过时（日志格式演变） | Agent 可检测"未见过的模板"→触发 KG 增量更新 |

### 4.2 目前是否有"TKG+Agent"直接用于 RCA 的研究？→ **尚未出现明确以此为题的高质量论文，但多个相关工作在边界上**

- **最近接的**：**KAIOps**（ASE 2025 Industry Showcase，快手）在生产中同时使用了时间上下文编码 + KG + LLM，但其 LLM 部分更偏向"辅助总结"而非自主 agent。**ALICE**（NeurIPS 2025）用 agent 构建 KG 并基于 KG 推理，但其 KG 是程序依赖图，非时序故障 KG。
- **最直接前驱**：**UniDiag**（2024）提供了 TKG 融合多模态的路径，**mABC**（2024）提供了多 agent RCA 协作的路径。两者若结合——以 TKG 为 agent 的共享世界模型，以 multi-agent 为推理与行动的执行器——即形成完整的"TKG+Agent RCA"方案。
- **在写论文前应高度关注的竞争者**：DynaCausal 团队（CUHK-Shenzhen 的 Pinjia He 组）在动态因果关系建模上非常强，且其 RCA benchmark 工作暗示他们对评测的全面思考——该组若将 Agent 引入因果推理，会很快出货。

---

## 五、如果要做：TKG+Agent RCA 的架构建议

### 5.1 系统架构（概念层）

```
┌─────────────────────────────────────────────────────────────────────┐
│                    TKG-Agent RCA 系统                                │
│                                                                      │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐         │
│  │ 观测Agent │   │ 诊断Agent │   │ 修复Agent │   │ 学习Agent │         │
│  │ (Monitor) │──▶│(Diagnose)│──▶│ (Remedy) │──▶│ (Learn)  │         │
│  │           │   │           │   │           │   │           │         │
│  │ 异常检测  │   │ 根因推理  │   │ 修复执行  │   │ TKG更新   │         │
│  │ 日志/指标 │   │ 假设检验  │   │ 回滚/重启 │   │ 新实体/边 │         │
│  │ /追踪采集 │   │ 因果验证  │   │ 配置变更  │   │ 质量审计  │         │
│  └─────┬─────┘   └─────┬─────┘   └─────┬─────┘   └─────┬─────┘         │
│        │               │               │               │               │
│        └───────────────┼───────────────┼───────────────┘               │
│                        ▼               ▼                               │
│                 ┌──────────────────────────┐                           │
│                 │   时序知识图谱 (TKG)      │                           │
│                 │   (Neo4j / 图数据库)      │                           │
│                 │                          │                           │
│                 │  四元组: (实体, 关系,     │                           │
│                 │          实体, 时间戳)    │                           │
│                 │                          │                           │
│                 │  节点: 服务/组件/日志模板 │                           │
│                 │        /配置项/指标       │                           │
│                 │  边: causes/leads_to/     │                           │
│                 │      depends_on/triggers  │                           │
│                 │  时间属性: 首次发生/最后   │                           │
│                 │     发生/频率/置信度      │                           │
│                 └──────────────────────────┘                           │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.2 关键技术栈映射（从两篇论文提取）

| 需求 | 可借鉴来源 |
|---|---|
| 多 Agent 编排与状态管理 | Brodimas et al. 的 LangGraph + Graph State（messages/next/rationale）模式 |
| ReAct 推理 + Tool Calling | Brodimas et al. 的 ReAct agent + MCP-Tool 封装模式 |
| 日志→实体/关系提取 | AetherLog 的 LLM 实体提取 + 多种 prompting 策略 |
| 实体嵌入与语义消歧 | AetherLog 的 BigLog + DBSCAN 聚类 + 质心归一化 |
| 知识图谱存储与检索 | AetherLog 的 Neo4j + Top-K（K=3）余弦相似检索 |
| 时序建模 | UniDiag 的 R-GCN + GRU；TA-ComplEx 的 time-aware embedding |
| LLM 幻觉抑制 | mABC 的多 agent 去中心化投票 + AetherLog 的 KG 约束 |
| Human-in-the-loop | Brodimas et al. 的中断点机制 |

### 5.3 创新点候选（基于现有论文的留白）

1. **将 AetherLog 的静态 KG 升维为时序 KG**：在实体归一边增加时间戳维度，关系从"causes"变为"causes_at_t"，支持时态查询（"在过去 24 小时内，有哪些事件先于该磁盘错误发生？"）
2. **Agent 驱动 KG 的主动演化**：AetherLog 已有"低相似度→推理新根因→生成新三元组→写入 KG"的雏形，TKG+Agent 可将其扩展为完整的持续学习闭环（含质量审计 agent）
3. **多模态对齐**：借鉴 UniDiag 的 metrics/logs/traces 融合，让不同 agent 分别消费不同模态、在 TKG 层面统一表示
4. **预防性推理**：TKG 记录时间间隔，Agent 可在"故障 A 发生后 42.3 秒大概率出现故障 B"的模式上做预测式干预

---

## 六、文献质量筛选参考

撰写方法/引言时可重点引用的**近两年 CCF-B/二区以上**文献：

| # | 论文 | 年份 | Venue | CCF 等级 | 直接相关性 |
|---|------|------|-------|----------|-----------|
| 1 | **AetherLog** | 2025 | ISSRE | CCF-B | ★★★★★ LLM+KG for RCA |
| 2 | **UniDiag** | 2024 | IEEE TSC | CCF-A | ★★★★★ TKG for RCA |
| 3 | **DynaCausal** | 2025 | arXiv* | — | ★★★★☆ 动态因果 RCA |
| 4 | **mABC** | 2024 | EMNLP Findings | CCF-B | ★★★★☆ Multi-agent RCA |
| 5 | **KAIOps** | 2025 | ASE Industry | CCF-A | ★★★★☆ TKG+LLM 生产系统 |
| 6 | **ALICE** | 2025 | NeurIPS Expo | CCF-A 顶会 | ★★★★☆ Agentic RCA |
| 7 | Brodimas et al. **Intent-Based Agentic AI** | 2025 | IEEE OJCOMS | SCI Q2 | ★★★☆☆ Agentic 编排模式 |
| 8 | **TA-ComplEx** | 2025 | Comput. Ind. Eng. | 中科院一区 | ★★★☆☆ TKG 故障预测 |
| 9 | **LogKG** | 2023 | ISSRE | CCF-B | ★★★☆☆ KG for RCA（AetherLog baseline）|

> *DynaCausal 的 arXiv 版本已公开，正式 venue 待确认；其方法学质量高，但引用时应注明 preprint 状态。

---

## 七、结论

**是的，时序知识图谱 + Agent 在根因分析领域具备高度的理论可行性，且技术栈成熟度已足够支撑原型构建。** 关键判断如下：

1. **TKG 侧**：UniDiag（CCF-A, 2024）已充分验证 TKG 在多模态微服务故障诊断中的有效性，AetherLog（CCF-B, 2025）验证了 LLM 构建 KG（含聚类消歧）用于 RCA 的可复现路径。两者的"下一代"——将 LLM 构建的 KG 从静态升级为时序——是直接可操作的技术路径。

2. **Agent 侧**：mABC（CCF-B, 2024）验证了多 agent 协作 RCA 的有效性，Brodimas et al.（2025）提供了 agentic 编排的工程蓝本。将"RCA 决策链"建模为 ReAct agent 的多步推理循环，在理论与工程上均有先例。

3. **创新空间明确**：目前**尚未出现**将 TKG 作为 Agent 共享世界模型、Agent 主动维护 TKG 的 RCA 完整方案。最接近的是 KAIOps（2025，生产部署）和 ALICE（2025，agent+KG），但它们均未将"时序 KG"作为核心卖点。这构成了一个**有明确空白、有可复用基础、有工程可行性**的研究切入点。
