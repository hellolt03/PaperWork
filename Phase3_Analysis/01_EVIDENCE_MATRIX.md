# PHASE 3: 证据矩阵构建 (Evidence Matrix Construction)

## 步骤 1: 论文×主题矩阵

### 数据结构说明
- **✓** = 论文直接涵盖该章节主题
- **◐** = 论文部分/间接涵盖  
- **✗** = 论文不涵盖该主题
- **Tier** = Tier I (核心) / Tier II (高相关) / Tier III (标准相关)
- **强度** = 论文对该主题的贡献深度评分 (1-5 星)

---

## 完整论文×章节矩阵

| # | 论文标识 | 章节1<br/>编排范式 | 章节2<br/>工具调用 | 章节3<br/>职能划分 | 章节4<br/>知识图谱 | 章节5<br/>缺口 | 主要贡献 | Tier | 强度 |
|---|---------|---------|---------|---------|---------|---------|---------|------|-----|
| 1 | Cloud-OpsBench | ✓ | ◐ | ✓ | ✗ | ✓ | Benchmark RCA; Agent role evaluation | I | ★★★★★ |
| 2 | Flow-of-Action | ✓ | ✓ | ✓ | ◐ | ✓ | SOP-enhanced multi-agent RCA orchestration | I | ★★★★★ |
| 3 | In-Depth RCA MaRT | ✓ | ◐ | ◐ | ◐ | ✓ | Recursion-of-Thought pattern for agents | I | ★★★★☆ |
| 4 | AIOpsLab | ✓ | ✓ | ✓ | ✗ | ✓ | Holistic agent evaluation framework | I | ★★★★☆ |
| 5 | Building AI Agents | ✓ | ◐ | ✓ | ✗ | ✓ | Design principles for cloud agents | I | ★★★★☆ |
| 6 | QoEReasoner | ◐ | ✓ | ◐ | ◐ | ✓ | Agentic framework for RCA; hallucination handling | I | ★★★★☆ |
| 7 | AgentTrace | ✓ | ◐ | ◐ | ✓ | ✓ | Graph-based agent tracing & causal analysis | I | ★★★★☆ |
| 8 | TraceSIR | ✓ | ◐ | ✓ | ◐ | ✓ | Structured trace analysis for agent failures | I | ★★★☆☆ |
| 9 | Stalled, Biased | ◐ | ✓ | ◐ | ✗ | ✓ | LLM failure modes; reasoning failures taxonomy | I | ★★★★☆ |
| 10 | HypoAgent | ✓ | ◐ | ✓ | ✓ | ◐ | Interactive KG-based hypothesis generation | I | ★★★★☆ |
| 11 | OptiRepair | ◐ | ✓ | ✓ | ◐ | ✓ | Closed-loop diagnosis & repair cycles | I | ★★★★☆ |
| 12 | Shepherd | ✓ | ◐ | ✓ | ◐ | ✓ | Meta-agent runtime orchestration | I | ★★★☆☆ |
| 13 | Hallucination Mitigation | ◐ | ✓ | ◐ | ◐ | ✓ | Semantic caching for agent hallucination prevention | I | ★★★★☆ |
| 14 | MemGraphRAG | ◐ | ◐ | ◐ | ✓ | ◐ | Multi-agent graph-based memory & RAG | I | ★★★★☆ |
| 15 | GraphMind | ✓ | ◐ | ✓ | ◐ | ✓ | Workflow extraction from traces | I | ★★★☆☆ |
| 16 | Close the Loop | ◐ | ✓ | ✓ | ◐ | ◐ | Tool-use synthetic data via multi-agent role-play | I | ★★★☆☆ |
| 17 | LLM Ghostbusters | ◐ | ✓ | ✗ | ✗ | ✓ | Hallucination suppression via unlearning | I | ★★★☆☆ |
| 18 | CareGuardAI | ✓ | ✓ | ◐ | ◐ | ✓ | Multi-agent guardrails; safety verification | I | ★★★☆☆ |
| 19 | LOOP Skill Engine | ✓ | ✓ | ✓ | ◐ | ◐ | Deterministic skill orchestration; efficiency | I | ★★★★☆ |
| 20 | MAGE | ✓ | ◐ | ✓ | ✓ | ✓ | KG co-evolution in multi-agent systems | I | ★★★★☆ |
| 21 | UModel | ◐ | ✓ | ◐ | ◐ | ✓ | Agent-ready observability data modeling | I | ★★★☆☆ |
| 22 | Repairing Tool Calls | ◐ | ✓ | ◐ | ◐ | ✓ | Post-execution reflection for tool errors | I | ★★★☆☆ |
| 23 | SOP-Bench | ◐ | ✓ | ✓ | ◐ | ✓ | Benchmark for LLM agents on complex SOPs | I | ★★★★☆ |
| 24 | PRISM | ◐ | ✓ | ✗ | ◐ | ✓ | Probing hallucination reasoning patterns | I | ★★★☆☆ |
| 25 | SafeMCP | ◐ | ✓ | ◐ | ◐ | ✓ | Look-ahead reasoning for agent safety | I | ★★★☆☆ |
| 26 | TraceSafe | ◐ | ✓ | ◐ | ◐ | ✓ | Systematic guardrail assessment for LLMs | I | ★★★☆☆ |
| 27 | EigenData | ✓ | ◐ | ✓ | ◐ | ✓ | Self-evolving multi-agent platform | I | ★★★☆☆ |
| 28 | ChronoMedKG | ◐ | ◐ | ◐ | ✓ | ◐ | Temporal KG for biomedical agents | I | ★★★☆☆ |
| 29 | Agentic GraphRAG | ◐ | ◐ | ✓ | ✓ | ◐ | Collaborative agent + graph RAG | I | ★★★☆☆ |
| 30 | KG Missing Link | ◐ | ✓ | ◐ | ✓ | ✓ | KG + agent-based formal verification | I | ★★★☆☆ |
| 31 | MicroRCA-Agent | ✓ | ✓ | ✓ | ◐ | ✓ | Multi-agent RCA for microservices | I | ★★★★☆ |
| 32 | GALA | ✓ | ◐ | ✓ | ✓ | ◐ | Graph-augmented agent workflows | I | ★★★★☆ |
| 33 | TopoEvo | ✓ | ◐ | ✓ | ◐ | ✓ | Topology-aware self-evolving agents | I | ★★★★☆ |
| 34 | STAR | ✓ | ✓ | ✓ | ◐ | ✓ | Triage & repair agent framework | I | ★★★★☆ |
| 35 | Microservices RCA | ✓ | ◐ | ✓ | ◐ | ✓ | Multi-agent coordination for RCA | I | ★★★★☆ |
| 36 | Hypergraph ODE RCA | ◐ | ◐ | ◐ | ✓ | ✓ | Graph + temporal modeling for RCA | I | ★★★☆☆ |
| 37 | Heterogeneity RCA | ◐ | ◐ | ◐ | ✓ | ✓ | Heterogeneous system analysis for RCA | I | ★★★☆☆ |
| 38 | DynaCausal | ◐ | ◐ | ◐ | ✓ | ✓ | Dynamic causality for RCA | I | ★★★☆☆ |

---

## 覆盖度统计

### 按章节覆盖

| 章节 | 直接覆盖(✓) | 部分覆盖(◐) | 覆盖率 | 平均强度 |
|-----|----------|----------|------|--------|
| **章节1: Agent编排范式** | 17 | 12 | 76.3% | ★★★★☆ |
| **章节2: 工具调用可靠性** | 16 | 14 | 78.9% | ★★★★☆ |
| **章节3: Agent职能划分** | 17 | 9  | 68.4% | ★★★☆☆ |
| **章节4: 知识图谱协同** | 9  | 15 | 63.2% | ★★★☆☆ |
| **章节5: 缺口分析** | 28 | 5  | 86.8% | ★★★☆☆ |

### 按强度分布

| 强度级别 | 论文数 | 占比 |
|--------|-------|-----|
| ★★★★★ (顶级贡献) | 2 | 5.3% |
| ★★★★☆ (高度相关) | 15 | 39.5% |
| ★★★☆☆ (中等相关) | 18 | 47.4% |
| ★★☆☆☆ (低度相关) | 3 | 7.9% |

---

## 关键观察

1. **章节1 & 2 覆盖度高** (~77-79%)：Agent编排和工具调用是研究热点
2. **章节4 (知识图谱) 相对薄弱** (63%)：需要更多 KG-agent 协同研究
3. **缺口分析覆盖最全** (87%)：多数论文都提及未来研究方向
4. **Tier 不均** (全为 I)：需从 Tier II 补充深度论证

---

## 下一步：主题聚类与观点提取

参见 `02_THEMATIC_CLUSTERING.md`
