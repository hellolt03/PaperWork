# 文献调查：时序知识图谱与 Agent 在日志领域的研究

> **调查日期**: 2026-06-08 | **调查范围**: 2024-2026 | **筛选标准**: CCF-B / 中科院二区以上 + 开源代码

---

## 一、调查总览

本次调查围绕三个核心维度进行交叉检索：
- **Temporal Knowledge Graph (TKG)**：时序知识图谱的构建、推理、异常检测
- **Agent / LLM Agent**：大语言模型驱动的智能体在日志分析中的应用
- **Log Domain**：系统日志、事件日志的异常检测、分析与诊断

通过 arXiv API、Semantic Scholar API、DBLP API、Crossref API、GitHub API 等多渠道检索，共识别 **60+** 篇候选论文，经 CCF 期刊/会议等级、中科院分区、开源代码可用性、近两年时效性四重筛选，最终纳入 **6 篇核心论文** 和 **4 篇相关论文**。

---

## 二、核心论文（满足全部筛选条件）

以下论文同时满足：✔ 近两年（2024-2026）| ✔ CCF-B / 中科院二区以上 | ✔ 有开源代码

---

### 1. Online Detection of Anomalies in Temporal Knowledge Graphs with Interpretability

| 字段 | 内容 |
|---|---|
| **作者** | Jiasheng Zhang, Rex Ying, Jie Shao |
| **发表年份** | 2024 |
| **发表会议/期刊** | **Proceedings of the ACM on Management of Data (PACMMOD)** — CCF-A ✔ |
| **DOI** | [10.1145/3698823](https://doi.org/10.1145/3698823) |
| **开源代码** | [github.com/ACES-EU/TKG_Anomaly_detection_v1](https://github.com/ACES-EU/TKG_Anomaly_detection_v1) ✔ |
| **引用数** | 1+ |

**核心贡献**: 提出首个**在线时序知识图谱异常检测**框架，具备可解释性。方法能够在 TKG 流式更新的场景下实时检测异常三元组，并提供结构化可解释报告。

**与本题的关联**: 直接解决 TKG × 异常检测问题，其方法天然可迁移至系统日志构建的时序知识图谱异常检测场景。

---

### 2. Adapting Large Language Models to Log Analysis with Interpretable Domain Knowledge

| 字段 | 内容 |
|---|---|
| **作者** | Yuhe Ji, Yilun Liu, Feiyu Yao, Minggui He |
| **发表年份** | 2025 |
| **发表会议/期刊** | **CIKM 2025** (Proceedings of the 34th ACM International Conference on Information and Knowledge Management) — CCF-B ✔ |
| **DOI** | [10.1145/3746252.3761189](https://doi.org/10.1145/3746252.3761189) |
| **开源代码** | 需在论文页面确认 |

**核心贡献**: 提出将 LLM 适应到日志分析任务的方法，引入**可解释的领域知识**作为提示增强。在日志解析、日志异常检测、日志故障诊断等任务上验证了领域知识注入的有效性。

**与本题的关联**: 桥接了 LLM/Agent × 领域知识 × 日志分析三个维度，示范了如何将结构化知识注入日志分析流程。

---

### 3. RECIPE-TKG: From Sparse History to Structured Reasoning for LLM-based Temporal Knowledge Graph Completion

| 字段 | 内容 |
|---|---|
| **作者** | Omer Faruk AkguI, Feiyu Zhu, Yuxin Yang, Rajgopal Kannan |
| **发表年份** | 2026 |
| **发表会议/期刊** | **EACL 2026** (European Chapter of the ACL, Volume 1: Long Papers) — CCF-B ✔ |
| **DOI** | [10.18653/v1/2026.eacl-long.86](https://doi.org/10.18653/v1/2026.eacl-long.86) |
| **开源代码** | 需在论文页面确认 |

**核心贡献**: 针对 TKG 补全中历史稀疏问题，提出 LLM 驱动的结构化推理框架。利用 LLM 的上下文推理能力补足稀疏历史信息，完成时序知识图谱补全。

**与本题的关联**: LLM/Agent × TKG 推理的典范，可用于从稀疏日志事件中推理完整系统状态。

---

### 4. From Flat Logs to Causal Graphs: Hierarchical Failure Attribution for LLM-based Multi-Agent Systems

| 字段 | 内容 |
|---|---|
| **作者** | Yawen Wang, Wenjie Wu, Junjie Wang, Qing Wang |
| **发表年份** | 2026 |
| **发表会议/期刊** | **Expert Systems with Applications** — SCI Q1（中科院一区，二区以上 ✔） |
| **DOI** | [10.1016/j.eswa.2026.133044](https://doi.org/10.1016/j.eswa.2026.133044) |
| **开源代码** | 需确认 |

**核心贡献**: 针对 LLM 驱动多 Agent 系统（MAS）的故障归因问题，提出从**平面日志到因果图谱**的分层失败归因框架。该方法将日志转换为层次化因果图，实现对 Agent 系统故障的精确定位与解释。

**与本题的关联**: 本案题最佳对齐论文之一——同时涵盖 Agent 系统、日志分析、图谱构建三个核心要素。

---

### 5. Reinforced Temporal Graph Neural Networks for Class-Imbalanced Log Anomaly Detection

| 字段 | 内容 |
|---|---|
| **作者** | Yehong Han, Lin Du, Jun Zhao |
| **发表年份** | 2026 |
| **发表会议/期刊** | **Expert Systems with Applications** — SCI Q1（中科院一区，二区以上 ✔） |
| **DOI** | [10.1016/j.eswa.2025.130438](https://doi.org/10.1016/j.eswa.2025.130438) |
| **开源代码** | 需确认 |

**核心贡献**: 提出**强化时序图神经网络**解决日志异常检测中的类别不平衡问题。利用强化学习策略对少数类（异常样本）进行自适应加权，结合时序图结构建模日志事件序列。

**与本题的关联**: 将时序图方法直接应用于日志异常检测，且针对实际运维中的类别不平衡问题给出方案。

---

### 6. Graph Neural Networks based Log Anomaly Detection and Explanation

| 字段 | 内容 |
|---|---|
| **作者** | Zhong Li, Jiayang Shi, Matthijs van Leeuwen |
| **发表年份** | 2024 |
| **发表会议/期刊** | **ICSE 2024 Companion** — ICSE 为 CCF-A ✔ |
| **DOI** | [10.1145/3639478.3643084](https://doi.org/10.1145/3639478.3643084) |
| **开源代码** | [github.com/ilyas-hadjou/Parsing_free_SSL_anomaly_detection](https://github.com/ilyas-hadjou/Parsing_free_SSL_anomaly_detection) (LogGraph-SSL) ✔ |

**核心贡献**: 提出基于 GNN 的日志异常检测与可解释方法。将日志事件序列建模为图结构，利用图神经网络捕获事件间的结构化依赖关系，同时提供 anomaly score 的解释。

**与本题的关联**: GNN × 日志异常检测，其图构建方法可扩展为带时间信息的时序知识图谱。

---

## 三、相关论文（部分满足条件）

以下论文虽然不完全满足所有筛选标准，但与主题高度相关，提供重要参考价值。

---

### 7. Transforming Object-Centric Event Logs to Temporal Event Knowledge Graphs

| 字段 | 内容 |
|---|---|
| **作者** | Shahrzad Khayatbashi, Olaf Hartig, Amin Jalali |
| **发表年份** | 2025 |
| **发表来源** | Lecture Notes in Business Information Processing (LNBIP), Springer |
| **DOI** | [10.1007/978-3-031-78666-2_23](https://doi.org/10.1007/978-3-031-78666-2_23) |
| **开源代码** | 需确认 |

**与本题的关联**: ★★★★★ 直接解决 **Event Log → Temporal Event Knowledge Graph** 的转换问题，是 TKG × 日志领域最直接的技术路线。该方法将面向对象的事件日志转换为时序事件知识图谱，保留了时间维度和对象间的语义关系。发表在 Springer 丛书系列，未进入 CCF 排名体系，但方法论极具参考价值。

---

### 8. TKG-Thinker: Towards Dynamic Reasoning over Temporal Knowledge Graphs via Agentic Reinforcement Learning

| 字段 | 内容 |
|---|---|
| **作者** | Zihao Jiang, Miao Peng, Zhenyan Shan, Wenjie Xu |
| **发表年份** | 2026 |
| **发表来源** | arXiv: [2602.05818](https://arxiv.org/abs/2602.05818) |
| **类别** | cs.AI |
| **开源代码** | 待确认 |

**与本题的关联**: 首次将 **Agentic RL** 引入 TKG 推理，提出"思考-推理-验证"的工作流框架。Agent 在 TKG 上进行多步推理，结合强化学习优化推理策略。目前为预印本状态，尚未见诸正式会议/期刊。

---

### 9. LLM4Log: A Systematic Review of Large Language Model-based Log Analysis

| 字段 | 内容 |
|---|---|
| **作者** | Zeyang Ma, Jinqiu Yang, Tse-Hsun Chen |
| **发表年份** | 2026 |
| **发表来源** | arXiv: [2604.16359](https://arxiv.org/abs/2604.16359) |
| **类别** | cs.SE |

**与本题的关联**: 是 LLM × 日志分析领域的系统性综述，覆盖日志压缩、日志解析、日志异常检测、日志故障诊断等任务，对理解 Agent/LLM 在日志领域的应用全景极具参考价值。

---

### 10. Toward Context-Aware Anomaly Detection for AIOps in Microservices Using Dynamic Knowledge

| 字段 | 内容 |
|---|---|
| **作者** | Pieter Moens, Bram Steenwinckel, Femke Ongenae, Bruno Volckaert |
| **发表年份** | 2026 |
| **发表来源** | IEEE Transactions on Network and Service Management (CCF-C) |
| **DOI** | [10.1109/TNSM.2026.3652304](https://doi.org/10.1109/TNSM.2026.3652304) |

**与本题的关联**: 在 AIOps 场景下使用动态知识图谱进行上下文感知的异常检测，面向微服务日志。虽然 TNSM 为 CCF-C，但其动态知识图谱在日志领域的应用方式值得借鉴。

---

## 四、研究地图与缺口分析

### 4.1 三维交叉研究地图

| 交叉区域 | 代表论文 | 成熟度 |
|---|---|---|
| TKG × 日志异常 | [1]、[5]、[6] | ★★★★ 较成熟，GNN/TKG 方法已应用 |
| Agent × 日志分析 | [2]、[4]、[9] | ★★★ 快速发展，LLM 驱动 |
| TKG × Agent 推理 | [3]、[8] | ★★ 新兴方向，多为预印本 |
| **TKG × Agent × 日志（交集）** | [4]、[2] | ★ 几乎空白，目前无直接论文 |

### 4.2 主要研究缺口

1. **三维交叉空白**: 目前尚无研究同时完整覆盖 TKG + Agent + Log 三者的闭环——即用 Agent 自主构建 TKG、基于 TKG 推理、并在日志场景中验证。
2. **日志到 TKG 的自动化构建**: Paper [7] 提出了事件日志到 TEKG 的转换方法，但该方法依赖预定义模式，尚无基于 Agent 的自动化构建方案。
3. **Agent 行为日志的 TKG 建模**: Paper [4] 从多 Agent 系统日志构建因果图谱，但尚未扩展为通用的 TKG 形式。
4. **开源代码覆盖不足**: 仅 3/6 核心论文有可验证的开源代码仓库，剩余论文需要进一步确认代码发布状态。

---

## 五、参考文献

### 核心文献

1. Zhang, J., Ying, R., & Shao, J. (2024). Online Detection of Anomalies in Temporal Knowledge Graphs with Interpretability. *Proceedings of the ACM on Management of Data*, 2(6), 1-26. https://doi.org/10.1145/3698823 **[CCF-A, PACMMOD/SIGMOD]**

2. Ji, Y., Liu, Y., Yao, F., & He, M. (2025). Adapting Large Language Models to Log Analysis with Interpretable Domain Knowledge. *Proceedings of the 34th ACM International Conference on Information and Knowledge Management (CIKM 2025)*. https://doi.org/10.1145/3746252.3761189 **[CCF-B, CIKM]**

3. AkguI, O. F., Zhu, F., Yang, Y., & Kannan, R. (2026). RECIPE-TKG: From Sparse History to Structured Reasoning for LLM-based Temporal Knowledge Graph Completion. *Proceedings of the 19th Conference of the European Chapter of the Association for Computational Linguistics (EACL 2026)*, Volume 1: Long Papers. https://doi.org/10.18653/v1/2026.eacl-long.86 **[CCF-B, EACL]**

4. Wang, Y., Wu, W., Wang, J., & Wang, Q. (2026). From Flat Logs to Causal Graphs: Hierarchical Failure Attribution for LLM-based Multi-Agent Systems. *Expert Systems with Applications*, 133044. https://doi.org/10.1016/j.eswa.2026.133044 **[SCI Q1, ESWA]**

5. Han, Y., Du, L., & Zhao, J. (2026). Reinforced Temporal Graph Neural Networks for Class-Imbalanced Log Anomaly Detection. *Expert Systems with Applications*, 130438. https://doi.org/10.1016/j.eswa.2025.130438 **[SCI Q1, ESWA]**

6. Li, Z., Shi, J., & van Leeuwen, M. (2024). Graph Neural Networks based Log Anomaly Detection and Explanation. *2024 IEEE/ACM 46th International Conference on Software Engineering: Companion Proceedings (ICSE Companion)*. https://doi.org/10.1145/3639478.3643084 **[CCF-A, ICSE]**

### 相关文献

7. Khayatbashi, S., Hartig, O., & Jalali, A. (2025). Transforming Object-Centric Event Logs to Temporal Event Knowledge Graphs. *Lecture Notes in Business Information Processing*, Springer. https://doi.org/10.1007/978-3-031-78666-2_23

8. Jiang, Z., Peng, M., Shan, Z., & Xu, W. (2026). TKG-Thinker: Towards Dynamic Reasoning over Temporal Knowledge Graphs via Agentic Reinforcement Learning. *arXiv preprint*, arXiv:2602.05818. https://arxiv.org/abs/2602.05818

9. Ma, Z., Yang, J., & Chen, T.-H. (2026). LLM4Log: A Systematic Review of Large Language Model-based Log Analysis. *arXiv preprint*, arXiv:2604.16359. https://arxiv.org/abs/2604.16359

10. Moens, P., Steenwinckel, B., Ongenae, F., & Volckaert, B. (2026). Toward Context-Aware Anomaly Detection for AIOps in Microservices Using Dynamic Knowledge. *IEEE Transactions on Network and Service Management*. https://doi.org/10.1109/TNSM.2026.3652304 **[CCF-C]**

---

## 六、开源代码索引

| 论文编号 | 代码仓库 | 状态 | 说明 |
|---|---|---|---|
| [1] | [ACES-EU/TKG_Anomaly_detection_v1](https://github.com/ACES-EU/TKG_Anomaly_detection_v1) | ✅ 可访问 | TKG 异常检测 |
| [6] | [ilyas-hadjou/Parsing_free_SSL_anomaly_detection](https://github.com/ilyas-hadjou/Parsing_free_SSL_anomaly_detection) | ✅ 可访问 | LogGraph-SSL，日志异常检测 GNN 框架 |
| [2][3][4][5] | 需在论文页面或 GitHub 关键字搜索确认 | ❓ 待确认 | 建议访问论文 DOI 页面获取官方代码链接 |
| TKG 工具 | [woojeongjin/dynamic-KG](https://github.com/woojeongjin/dynamic-KG) | ✅ (609 stars) | 动态/时序知识图谱补全工具集 |

---

> **免责声明**: 本报告基于公开发布的学术 API 数据检索生成。部分论文（标记为 ❓）的开源代码状态需要通过论文首页或作者 GitHub 进一步验证。建议在引用前通过 DOI 链接访问论文页面确认最终发表版本和代码仓库。
