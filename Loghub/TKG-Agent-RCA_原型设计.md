# TKG-Agent RCA 原型设计文档

**基座**：AetherLog (ISSRE 2025) 开源代码  
**设计日期**：2026-06-07  
**目标**：将 AetherLog 从"静态 KG + 固定管道"升级为"时序 KG + 自适应 Agent"的 RCA 原型系统

---

## 一、AetherLog 代码审计（基座分析）

### 1.1 仓库结构总览

```
AetherLog-main/AetherLog-main/
├── configs/
│   ├── config.yaml              ← 完整配置（含 hdbscan 配置项但代码未使用）
│   └── config_parser.py          ← YAML 配置加载 + CLI 参数合并
├── models/
│   └── prompt_templates/
│       └── rca_prompt.py         ← RCA prompt 模板（硬编码字符串）
├── scripts/
│   ├── preprocess.py             ← 日志预处理（提取 message 字段 → JSON）
│   ├── build_kg.py               ← KG 构建主脚本（import 了 4 个不存在的模块）
│   ├── align_entities.py         ← 实体对齐（⚠️ 用固定余弦阈值 0.8，非 DBSCAN）
│   ├── recall_entities.py        ← 实体召回（⚠️ 用 np.random.rand(512) 代替真实嵌入）
│   ├── rca_inference.py          ← RCA 推理主脚本（import 了 5 个不存在的模块）
│   └── evaluate.py               ← 评估（macro F1，需 pred.json + gold.json）
└── utils/
    ├── io.py                     ← JSON/txt/npy/pickle 读写工具
    ├── metrics.py                ← 分类指标 + MAP@k + 混淆矩阵
    └── summarizer.py             ← LLM 摘要（⚠️ 使用已废弃的 openai.Completion.create）
```

### 1.2 关键发现：论文—代码不一致

| 论文声明 | 代码实际 | 影响 |
|----------|---------|------|
| DBSCAN(ε=0.5, MinPts=3) 做实体聚类 | `align_entities.py` 使用固定余弦阈值 0.8 做贪心分组 | 论文核心卖点（密度自适应聚类）**未在代码中实现** |
| BigLog 预训练模型做实体嵌入 | `recall_entities.py` 使用 `np.random.rand(512)` | 语义检索是假的，**实际不可用** |
| Neo4j 图数据库存储 KG | `build_kg.py` 使用 `networkx.write_edgelist` 写文本文件 | KG 持久化降级为文本文件 |
| 三种 prompting 策略（Z/F/C）| `rca_prompt.py` 仅一个硬编码模板 | 消融实验的 Zero-shot/Few-shot/CoT 对比**无法复现** |
| config.yaml 中 `clustering_method: hdbscan` | 代码无 HDBSCAN 调用 | 配置项是**死代码** |

### 1.3 代码是骨架状态的证据

`build_kg.py` 第 9-11 行尝试从**不存在的模块**导入：
```python
from entity_extraction import extract_entities       # 模块不存在
from entity_embedding import generate_embeddings      # 模块不存在
from entity_alignment import align_entities           # 模块不存在（scripts/ 下有一个同名但不同路径）
```

`rca_inference.py` 第 7-10 行同样：
```python
from entity_recall import recall_entities        # 模块不存在
from rca_prompt import generate_rca_prompt       # 模块不存在
from llm_inference import get_llm_response       # 模块不存在
from evaluation import evaluate                  # 模块不存在
```

`config_parser.py` 第 14 行甚至提到了另一个项目名：
```python
parser = argparse.ArgumentParser(description="SmartRCA Configuration")
                                            # ↑ "SmartRCA" 而非 "AetherLog"
```

**结论**：AetherLog 的开源代码是一份**结构完整但实现空缺的骨架**。这既是挑战（需要自行实现核心模块），也是机会（架构灵活，可以直接在此基础上叠加 TKG + Agent 能力）。

---

## 二、原型设计目标

### 2.1 补全 AetherLog 的缺失模块（v0 基线）

将论文中描述但代码未实现的部分补全到**可运行**状态：
- 实体抽取（LLM-based entity extraction 的三种 prompting 策略）
- 实体嵌入（BigLog / sentence-transformers）
- 聚类对齐（DBSCAN / HDBSCAN — 先在代码层面实现论文的 DBSCAN）
- KG 持久化（Neo4j / 至少 networkx → JSON 序列化）
- LLM RCA 推理（Chat Completion API + RCA prompt 构建）
- 评估（端到端 pipeline）

### 2.2 新增 TKG 层（v1 升级）

在 v0 基础上将静态 KG 升级为时序 KG：
- 实体关系从二元 `(h, r, t)` 变为含时间戳的四元组 `(h, r, t, timestamp)`
- 支持时态查询："事件 A 与事件 B 的时间间隔"
- 滑动窗口：仅保留最近 N 天的活跃关系

### 2.3 新增 Agent 层（v2 升级）

在 v1 基础上引入 Agentic 编排：
- 将 RCA 推理链路拆分为多 agent 协作
- Agent 可以**在推理时动态调整**聚类/检索参数
- Human-in-the-loop 中断点

---

## 三、原型架构总览

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                        TKG-Agent RCA 原型系统                                    │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │                        v2: Agent 编排层                                    │ │
│  │  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌─────────┐ │ │
│  │  │ Observer │──▶│ Diagnoser│──▶│ Verifier │──▶│ Remediator│──▶│ Learner │ │ │
│  │  │  Agent   │   │  Agent   │   │  Agent   │   │  Agent   │   │  Agent  │ │ │
│  │  │          │   │          │   │          │   │          │   │         │ │ │
│  │  │ 异常检测  │   │ 根因推理  │   │ 假设验证  │   │ 修复建议  │   │ KG 演化 │ │ │
│  │  └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬────┘ │ │
│  │       └──────────────┴──────────────┴──────────────┴──────────────┘      │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                      │                                          │
│  ┌───────────────────────────────────┼───────────────────────────────────────┐ │
│  │                        v1: TKG 层                                          │ │
│  │                                   │                                        │ │
│  │  ┌────────────────────────────────┼────────────────────────────────────┐  │ │
│  │  │  TemporalEntityGraph           ▼                                    │  │ │
│  │  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐             │  │ │
│  │  │  │ TimeIndexed   │   │ SlidingWindow│   │ TemporalQuery│             │  │ │
│  │  │  │ QuadStore     │   │ Manager      │   │ Engine       │             │  │ │
│  │  │  │ (h,r,t,ts,Δt) │   │ (N-day window│   │ (before/after│             │  │ │
│  │  │  │               │   │  pruning)    │   │  /between)   │             │  │ │
│  │  │  └──────────────┘   └──────────────┘   └──────────────┘             │  │ │
│  │  └─────────────────────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                      │                                          │
│  ┌───────────────────────────────────┼───────────────────────────────────────┐ │
│  │                        v0: 补全的 AetherLog 基线                           │ │
│  │                                   │                                        │ │
│  │  ┌──────────┐   ┌──────────┐   ┌─┴────────┐   ┌──────────┐   ┌──────────┐│ │
│  │  │ Entity   │──▶│ Entity   │──▶│ Cluster  │──▶│ KG Build │──▶│ RCA      ││ │
│  │  │ Extract  │   │ Embed    │   │ (DBSCAN) │   │ (Neo4j)  │   │ Infer    ││ │
│  │  │ (3 prompt│   │ (BigLog) │   │          │   │          │   │ (GPT-4)  ││ │
│  │  │  modes)  │   │          │   │          │   │          │   │          ││ │
│  │  └──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘│ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## 四、v0：补全 AetherLog 基线（模块级设计）

### 4.1 模块清单与实现方案

| 原代码缺失模块 | 新文件路径 | 实现方案 | 依赖 |
|---|---|---|---|
| `entity_extraction` | `src/entity_extraction.py` | 封装三个函数 `extract_zero_shot()`, `extract_few_shot()`, `extract_cot()`，调用 OpenAI Chat Completion API；prompt 模板从论文 Fig.4 还原 | `openai` |
| `entity_embedding` | `src/entity_embedding.py` | 加载 sentence-transformers 的 BigLog 模型（若 HuggingFace 无此模型则回退到 `all-MiniLM-L6-v2` 或 `e5-large-v2`）；提供 `generate_embeddings()` 接口 | `sentence-transformers` |
| `entity_alignment` | `src/entity_alignment.py` | 替换现有的贪心阈值方案，实现论文描述的 DBSCAN(ε=0.5, MinPts=3) + k-distance 图自动选 ε 的方法；额外提供 `HDBSCANAdapter` 做对照 | `sklearn.cluster.DBSCAN`, `hdbscan` |
| `llm_inference` | `src/llm_inference.py` | 封装 `get_llm_response(prompt, config)`，统一调用 OpenAI Chat Completion（`gpt-3.5-turbo` / `gpt-4`），支持 temperature 和 max_tokens 配置，含 retry（最多 3 次） | `openai` |
| `rca_prompt` | `src/rca_prompt.py` | 从 `models/prompt_templates/rca_prompt.py` 提取模板 + 加入三种 prompting 策略的动态构建；`generate_rca_prompt()` 接收故障摘要 + Top-K 实体 + 模式选择参数 | — |
| `entity_recall` | `src/entity_recall.py` | 从 `scripts/recall_entities.py` 重构：**替换随机向量为真实 BigLog embedding**；`recall_entities(log_text, kg_embeddings, top_k)` | `sklearn.metrics.pairwise.cosine_similarity` |
| `evaluation` | `src/evaluation.py` | 从 `scripts/evaluate.py` 扩展：增加 micro/macro/weighted F1、Top-K accuracy、MAP@K、每类指标；`evaluate(preds, golds, config)` | `sklearn.metrics` |

### 4.2 关键实现细节

#### entity_extraction.py — 三种 prompting 策略

```python
# 从论文 Fig.4 还原的三个 prompt 模板

ZERO_SHOT_TEMPLATE = """
Instruction: The following log case is associated with the root cause "{root_cause_label}".
Extract key entities and their semantic relations, including components, operations, states, and critical parameters.
Log: {log_content}
Output:
Entities: [Entity1, Entity2, ...]
Relations: [(EntityA, Relation, EntityB), ...]
"""

FEW_SHOT_TEMPLATE = """
Instruction: The following are annotated examples for extracting entities and semantic relations based on root cause labels.
Example 1:
Root Cause: "Database Connection fault"
Log: "[17:22:03] Database connection failed due to timeout. Application retries the connection after 5 seconds."
Entities: [Database, connection, timeout, application, retries]
Relations: [(Database, causes, connection fault), (connection, blocked by, timeout), (application, retries, connection)]
{more_examples}
Now extract from the following:
Root Cause: "{root_cause_label}"
Log: {log_content}
Output:
Entities: [...]
Relations: [...]
"""

COT_TEMPLATE = """
Instruction: The following log case is associated with the root cause "{root_cause_label}".
First, reason through the fault step-by-step to identify cause-effect relationships.
Then extract relevant entities and their semantic relations accordingly.
Log: {log_content}
Output:
Entities: [Entity1, Entity2, ...]
Relations: [(EntityA, Relation, EntityB), ...]
Reasoning: [Step-by-step explanation]
"""

def extract_entities(logs, method="zero_shot", model="gpt-3.5-turbo", examples=None):
    """统一入口：method ∈ {"zero_shot", "few_shot", "cot"}"""
    if method == "zero_shot":
        return _extract_zero_shot(logs, model)
    elif method == "few_shot":
        return _extract_few_shot(logs, model, examples)
    elif method == "cot":
        return _extract_cot(logs, model)
```

#### entity_alignment.py — 从固定阈值升级为 DBSCAN

```python
import numpy as np
from sklearn.cluster import DBSCAN
from sklearn.neighbors import NearestNeighbors

def _estimate_epsilon(embeddings, min_pts=3):
    """用 k-distance 图自动估计 ε（论文描述的方法）"""
    nbrs = NearestNeighbors(n_neighbors=min_pts).fit(embeddings)
    distances, _ = nbrs.kneighbors(embeddings)
    k_distances = np.sort(distances[:, -1])
    # 寻找 elbow point（简化：取最大斜率变化点）
    diffs = np.diff(k_distances)
    elbow_idx = np.argmax(diffs)
    return k_distances[elbow_idx]

def align_entities(entities, embeddings, method="dbscan", eps=None, min_pts=3):
    """实体对齐统一接口：method ∈ {"dbscan", "hdbscan", "cosine_threshold"}"""
    if eps is None:
        eps = _estimate_epsilon(embeddings, min_pts)
    
    if method == "dbscan":
        clustering = DBSCAN(eps=eps, min_samples=min_pts, metric='cosine').fit(embeddings)
        labels = clustering.labels_
    elif method == "hdbscan":
        import hdbscan
        clustering = hdbscan.HDBSCAN(min_cluster_size=min_pts, metric='euclidean')
        labels = clustering.fit_predict(embeddings)
    elif method == "cosine_threshold":
        # 保留 AetherLog 原实现的阈值方案作为 baseline
        labels = _cosine_threshold_clustering(embeddings, threshold=0.8)
    
    # labels → groups（与现有 align_entities 兼容的输出格式）
    groups = _labels_to_groups(entities, labels)
    return groups
```

### 4.3 修改现有文件的最小变更集

| 文件 | 变更 |
|------|------|
| `scripts/align_entities.py` | 改为从 `src/entity_alignment` 导入 DBSCAN 方法，替换固定余弦阈值 |
| `scripts/recall_entities.py` | 删除 `np.random.rand(512)`，接入真实 BigLog embedding |
| `scripts/build_kg.py` | 修改 import 路径指向 `src/` 下的新模块 |
| `scripts/rca_inference.py` | 修改 import 路径指向 `src/` 下的新模块 |
| `utils/summarizer.py` | 将 `openai.Completion.create` 升级为 `openai.ChatCompletion.create` |
| `configs/config_parser.py` | 修复 `description="SmartRCA"` → `"AetherLog"` |

---

## 五、v1：TKG 层设计

### 5.1 核心数据结构

```python
# src/temporal_kg.py

from dataclasses import dataclass
from datetime import datetime
from typing import Optional
import networkx as nx

@dataclass
class TemporalQuad:
    """时序知识图谱的四元组"""
    head: str          # 头实体
    relation: str      # 关系类型
    tail: str          # 尾实体
    timestamp: datetime  # 事件发生时间
    confidence: float = 1.0  # 置信度（Agent 推理的结果可以 < 1.0）

class TemporalKnowledgeGraph:
    """
    TKG 核心类
    
    底层存储策略：
    - 短期（热数据）：DiGraph，dict of (h,r,t) → list[timestamps]，内存驻留
    - 长期（冷数据）：JSONL 持久化，按天分片
    """
    
    def __init__(self, window_days: int = 30):
        self.window_days = window_days
        self.quads: list[TemporalQuad] = []        # 全量四元组列表
        self._edge_times: dict[tuple, list[datetime]] = {}  # (h,r,t) → [t1, t2, ...]
        self._node_first_seen: dict[str, datetime] = {}
        self._node_last_seen: dict[str, datetime] = {}
    
    def add_quad(self, quad: TemporalQuad):
        """插入四元组"""
        key = (quad.head, quad.relation, quad.tail)
        if key not in self._edge_times:
            self._edge_times[key] = []
        self._edge_times[key].append(quad.timestamp)
        self.quads.append(quad)
        
        # 维护节点的时间元数据
        for node in [quad.head, quad.tail]:
            if node not in self._node_first_seen:
                self._node_first_seen[node] = quad.timestamp
            if node not in self._node_last_seen or quad.timestamp > self._node_last_seen[node]:
                self._node_last_seen[node] = quad.timestamp
    
    def add_from_aetherlog_kg(self, kg: nx.Graph, timestamp: datetime):
        """将 AetherLog 的静态 KG 节点/边转为 TKG 的四元组（作为快照导入）"""
        for u, v, data in kg.edges(data=True):
            self.add_quad(TemporalQuad(
                head=str(u),
                relation=data.get('relation', 'cooccurs_with'),
                tail=str(v),
                timestamp=timestamp,
                confidence=data.get('weight', 1.0)
            ))
    
    def query_before(self, entity: str, t: datetime, n: int = 10) -> list[TemporalQuad]:
        """查询：在时间 t 之前，与 entity 相关的事件"""
        candidates = [q for q in self.quads 
                      if (q.head == entity or q.tail == entity) and q.timestamp < t]
        return sorted(candidates, key=lambda x: x.timestamp, reverse=True)[:n]
    
    def query_causal_chain(self, start_entity: str, end_entity: str, 
                           max_hops: int = 5) -> list[list[TemporalQuad]]:
        """查询：从 start_entity 到 end_entity 的因果路径（按时间约束）"""
        # 使用 BFS + 时间单调性约束（后面的时间必须 ≥ 前面的时间）
        paths = []
        # ... BFS with monotonic time constraint
        return paths
    
    def prune_window(self, reference_time: datetime):
        """滑动窗口剪枝：移除早于 window_days 之前的四元组"""
        cutoff = reference_time - timedelta(days=self.window_days)
        self.quads = [q for q in self.quads if q.timestamp >= cutoff]
        # 同步更新 _edge_times
        self._edge_times = {k: [t for t in times if t >= cutoff] 
                           for k, times in self._edge_times.items()}
    
    def to_static_snapshot(self, reference_time: datetime) -> nx.DiGraph:
        """降维：将 TKG 在 reference_time 时刻的快照转为静态 DiGraph（兼容 AetherLog 下游）"""
        G = nx.DiGraph()
        for q in self.quads:
            if q.timestamp <= reference_time:
                G.add_edge(q.head, q.tail, relation=q.relation, confidence=q.confidence)
        return G
```

### 5.2 与 AetherLog v0 的集成点

```
原始 AetherLog 流程:
  logs → entity_extraction → embedding → clustering → static KG (networkx) → RCA

v1 TKG 流程:
  logs (含时间戳) 
    → entity_extraction (保留原始日志时间戳)
    → embedding 
    → clustering (同 v0)
    → TKG.add_from_aetherlog_kg(kg, timestamp)  ← 新增：静态 KG → 时序四元组
    → TKG.query_causal_chain(...)               ← 新增：时态约束的因果路径查询
    → RCA (prompt 中增加时间上下文)
```

具体地，修改 `scripts/rca_inference.py` 的 prompt 构建步骤：
```python
# 原：仅 Top-K 余弦相似实体
top_k_entities = recall_entities(log_text, recall_results, top_k=5)

# 新：附加时序因果链
temporal_context = tkg.query_before(entity, log_timestamp, n=5)
causal_chain = tkg.query_causal_chain(entity, root_cause_candidate)
rca_prompt = generate_rca_prompt_with_temporal(
    log_text, top_k_entities, temporal_context, causal_chain, config
)
```

### 5.3 持久化方案

```python
# 按天分片的 JSONL 持久化（简单可审计，避免引入 Neo4j 的部署复杂度）
# data/tkg/2026-06-01.jsonl
# data/tkg/2026-06-02.jsonl
# ...

def save_shard(self, date: str, path: str):
    shard_quads = [q for q in self.quads 
                   if q.timestamp.strftime('%Y-%m-%d') == date]
    with open(path, 'w') as f:
        for quad in shard_quads:
            f.write(json.dumps({
                'head': quad.head,
                'relation': quad.relation,
                'tail': quad.tail,
                'timestamp': quad.timestamp.isoformat(),
                'confidence': quad.confidence
            }) + '\n')
```

---

## 六、v2：Agent 编排层设计

### 6.1 Agent 定义

使用 LangGraph 作为编排引擎（借鉴 Brodimas et al. 2025 的模式），五个 agent 各有明确的 system prompt + 工具集合：

```python
# src/agents.py

AGENT_DEFINITIONS = {
    "observer": {
        "role": "观测 Agent — 收集并总结故障信号",
        "system_prompt": """You are the Observer Agent in an RCA system.
Your job is to:
1. Read raw fault logs and extract the key abnormal events.
2. Summarize the temporal sequence of events in chronological order.
3. Identify which entities (services, components, resources) are involved.
4. Flag any anomalous patterns (e.g., repeated timeouts, cascading errors).

Output format:
{
  "abnormal_events": [{"entity": "...", "event": "...", "timestamp": "..."}],
  "suspected_entities": ["entity1", "entity2"],
  "temporal_summary": "Step-by-step fault timeline..."
}
""",
        "tools": ["run_log_parser", "run_anomaly_detector", "query_metrics_api"]
    },
    
    "diagnoser": {
        "role": "诊断 Agent — 在 TKG 上推理根因",
        "system_prompt": """You are the Diagnoser Agent. 
You receive abnormal events from the Observer.
Your job is to:
1. For each suspected entity, query the Temporal Knowledge Graph for historical fault patterns.
2. Identify causal chains: which event triggered which.
3. Propose a ranked list of root cause candidates with confidence scores.
4. If the TKG returns low-similarity results, suggest that a NOVEL fault type may be involved.

IMPORTANT: When TKG retrieval quality is poor (cosine similarity < 0.6 or coverage < 50%):
- Call `adjust_clustering_params` to try alternative DBSCAN parameters
- If still poor after 2 retries, mark as "novel_pattern" instead of forcing a match.""",
        "tools": ["query_tkg", "run_local_dbscan", "adjust_clustering_params", 
                  "check_embedding_quality"]
    },
    
    "verifier": {
        "role": "验证 Agent — 对诊断结果做交叉验证",
        "system_prompt": """You are the Verifier Agent.
Your job is to challenge the Diagnoser's proposed root cause:
1. Can the proposed root cause explain ALL observed abnormal events?
2. Are there alternative explanations (e.g., two independent faults coinciding)?
3. Is there counter-evidence in the logs that contradicts the proposed cause?
4. Check for temporal plausibility: does the cause precede its effects?

Output: VERIFIED / NEEDS_REVISION / CONTRADICTED""",
        "tools": ["query_tkg", "query_metric_history", "check_temporal_order"]
    },
    
    "remediator": {
        "role": "修复 Agent — 建议修复动作",
        "system_prompt": """You are the Remediator Agent.
Based on the verified root cause, suggest concrete remediation actions.
Each action must include: what to do, which component, expected effect, rollback plan.
If the confidence is below 0.7, include a human-approval flag.""",
        "tools": ["query_runbook_kb", "check_config_history"]
    },
    
    "learner": {
        "role": "学习 Agent — 将新故障模式写入 TKG",
        "system_prompt": """You are the Learner Agent.
After RCA is complete (verified or not), your job is to:
1. Extract new (entity, relation, entity, timestamp) quads from this fault case.
2. Detect if any existing TKG entities should be merged with newly discovered ones.
3. Flag if the TKG quality is degrading (too many low-confidence edges, conflicting relations).
4. Propose TKG updates. DO NOT execute — wait for human approval if confidence < 0.8.""",
        "tools": ["add_tkg_quad", "merge_tkg_entities", "audit_tkg_quality"]
    }
}
```

### 6.2 LangGraph 编排图

```python
# src/graph.py

from langgraph.graph import StateGraph, END
from typing import TypedDict, Annotated
import operator

class GraphState(TypedDict):
    """借鉴 Brodimas et al. 的 Graph State 设计"""
    messages: Annotated[list, operator.add]  # 完整对话历史（含 agent 输出和 tool outputs）
    next_agent: str                          # 下一个应激活的 agent
    rationale: str                           # 选择该 agent 的理由（调试/审计用）
    # RCA 特定状态
    raw_logs: list[str]
    abnormal_events: list[dict]
    root_cause_candidates: list[dict]
    verified_root_cause: Optional[dict]
    remediation_plan: Optional[dict]
    tkg_updates: list[dict]
    human_approval_needed: bool
    hdbscan_params: dict                     # Agent 调整后的聚类参数

def build_rca_graph() -> StateGraph:
    workflow = StateGraph(GraphState)
    
    # 添加节点
    workflow.add_node("observer", observer_node)
    workflow.add_node("diagnoser", diagnoser_node)
    workflow.add_node("verifier", verifier_node)
    workflow.add_node("remediator", remediator_node)
    workflow.add_node("learner", learner_node)
    workflow.add_node("human_approval", human_approval_node)
    
    # 条件边（借鉴 Brodimas et al. 的 agent 自主路由）
    workflow.add_conditional_edges(
        "observer",
        router_observer,     # → "diagnoser" (正常) 或 "human_approval" (置信度过低)
        {"diagnoser": "diagnoser", "human_approval": "human_approval"}
    )
    workflow.add_conditional_edges(
        "diagnoser",
        router_diagnoser,    # → "verifier" 或重试本地聚类（循环最多 3 次）
        {"verifier": "verifier", "diagnoser": "diagnoser", "human_approval": "human_approval"}
    )
    workflow.add_conditional_edges(
        "verifier",
        router_verifier,     # VERIFIED → "remediator", NEEDS_REVISION → "diagnoser", CONTRADICTED → human
        {"remediator": "remediator", "diagnoser": "diagnoser", "human_approval": "human_approval"}
    )
    workflow.add_edge("remediator", "learner")
    workflow.add_edge("learner", END)
    workflow.add_edge("human_approval", END)
    
    workflow.set_entry_point("observer")
    return workflow.compile()
```

### 6.3 Agent 动态调 DBSCAN 的核心循环

这是 Diagnoser Agent 最关键的闭环——在 TKG 检索质量不足时，触发局部 DBSCAN 参数调整：

```python
# src/agents.py 中 Diagnoser 的工具实现

def run_local_dbscan(entities, embeddings, eps=0.5, min_pts=3):
    """局部 DBSCAN — 仅在当前查询相关实体的嵌入子集上运行"""
    return DBSCAN(eps=eps, min_samples=min_pts, metric='cosine').fit_predict(embeddings)

def adjust_clustering_params(state: GraphState, diagnosis: dict):
    """
    Agent 根据诊断结果决定如何调整参数。
    逻辑嵌入在 LLM 的 system prompt 中（参考前次分析的决策树），
    这里是工具执行层。
    """
    current_eps = state.get('hdbscan_params', {}).get('eps', 0.5)
    current_min_pts = state.get('hdbscan_params', {}).get('min_pts', 3)
    
    issues = diagnosis.get('clustering_issues', {})
    
    if issues.get('coverage_too_low'):
        # 查询实体未被覆盖 → 局部放宽
        new_eps = min(current_eps + 0.1, 1.5)
        new_min_pts = max(current_min_pts - 1, 2)
    elif issues.get('noise_ratio_too_high'):
        new_eps = min(current_eps + 0.15, 2.0)
        new_min_pts = current_min_pts
    elif issues.get('over_merging'):
        new_eps = max(current_eps - 0.1, 0.1)
        new_min_pts = current_min_pts
    else:
        new_eps, new_min_pts = current_eps, current_min_pts
    
    state['hdbscan_params'] = {'eps': new_eps, 'min_pts': new_min_pts}
    return state
```

### 6.4 Human-in-the-loop 中断点

参考 Brodimas et al. 的 `interrupt_before` 机制：

```python
# 在以下节点前设置中断点：
INTERRUPT_POINTS = [
    ("before", "remediator"),      # 执行修复前需人工确认
    ("before", "learner"),         # 写入新 KG 节点前需人工确认（置信度 < 0.8 时）
    ("after", "verifier"),         # 验证结果为 CONTRADICTED 时中断
]

# LangGraph 实现
graph = workflow.compile(
    interrupt_before=["remediator", "learner"],
)

# 当 graph 在中断点暂停时，用户 UI 显示：
# "拟执行操作：重启服务 A 的 Pod-3。是否继续？[批准] [拒绝] [修改参数后批准]"
```

---

## 七、实现路线图

```
Phase 0 (1-2 天)：环境搭建与 v0 补全
  ├── 创建 src/ 目录，实现 7 个缺失模块
  ├── 修复现有文件中的 import 路径和 API 调用
  ├── 用公开日志数据集（Loghub HDFS/BGL）做 smoke test
  └── 验证 v0 可端到端运行，复现论文报告的 F1 数量级

Phase 1 (2-3 天)：TKG 层集成
  ├── 实现 src/temporal_kg.py（TemporalKnowledgeGraph 类）
  ├── 修改 build_kg.py → 静态 KG 输出后自动导入 TKG
  ├── 修改 rca_inference.py → prompt 中增加时序上下文
  ├── 实现按天分片持久化
  └── 测试：对比 静态 KG RCA vs 时序 KG RCA 的 AC@1 差异

Phase 2 (3-5 天)：Agent 编排层
  ├── 安装 LangGraph + 实现 src/agents.py（5 个 agent 定义 + 工具）
  ├── 实现 src/graph.py（编排图 + 条件路由 + 中断点）
  ├── 实现 Diagnoser 的"聚类质量诊断→调整参数→重试"循环
  ├── 实现 Learner 的"新故障模式→TKG 增量更新"
  └── 测试：端到端 Agent 驱动 RCA，对比固定管道 baseline

Phase 3 (2-3 天)：评估 + 消融实验
  ├── 消融 1: v0 (fixed DBSCAN) vs v0+HDBSCAN vs v1 (TKG) vs v2 (Agent)
  ├── 消融 2: Agent 聚类调整循环 on/off → recall 差异
  ├── 消融 3: 时序上下文 on/off → AC@1 差异
  └── 指标：micro/macro F1, AC@1, AC@3, MRR, 平均推理延迟, LLM 调用次数

总计：约 8-13 天（单人）
```

---

## 八、关键设计决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 底层 embedding 模型 | `all-MiniLM-L6-v2`（回退）或 `e5-large-v2` | BigLog 模型大概率未在 HuggingFace 公开发布；`e5` 在文本相似度任务上表现接近，且支持中英文 |
| KG 持久化 | JSONL 按天分片（v1），可选 Neo4j（进阶）| JSONL 零部署依赖、易审计、Git 可版本化；Neo4j 增加运维成本，留作 production 升级项 |
| Agent 框架 | LangGraph | 借鉴了 Brodimas et al. (2025) 的工程方案；社区活跃，与 ReAct 模式天然匹配 |
| LLM API | OpenAI (gpt-3.5-turbo 默认, gpt-4 可选) | AetherLog 论文使用的模型；后期可接入本地 Llama3/Qwen 做成本对比 |
| 聚类方法 | DBSCAN（论文复现）→ HDBSCAN（基线升级）→ Agent+HDBSCAN（最终方案）| 渐进式：先确保能复现论文，再逐个替换组件 |

---

## 九、文件变更总览

```
新增文件:
  src/
  ├── __init__.py
  ├── entity_extraction.py       # 三种 prompting 策略的实体抽取
  ├── entity_embedding.py        # BigLog/sentence-transformer 嵌入
  ├── entity_alignment.py        # DBSCAN/HDBSCAN/余弦阈值 聚类
  ├── entity_recall.py           # 基于真实嵌入的 Top-K 召回
  ├── llm_inference.py           # OpenAI Chat Completion 封装
  ├── rca_prompt.py              # 动态 RCA prompt 构建 + 三种策略
  ├── evaluation.py              # 多指标评估
  ├── temporal_kg.py             # ★ TKG 核心类
  ├── agents.py                  # ★ 5 个 agent 定义 + 工具函数
  └── graph.py                   # ★ LangGraph 编排图

修改文件:
  scripts/align_entities.py      # 改为调用 src/entity_alignment
  scripts/recall_entities.py     # 删除 random embedding
  scripts/build_kg.py            # 修正 import 路径
  scripts/rca_inference.py       # 修正 import 路径 + 集成 TKG + Agent
  configs/config.yaml            # 增加 tkg、agent、hdbscan 配置项
  configs/config_parser.py       # 修复 description，增加新参数
  utils/summarizer.py            # 升级到 Chat Completion API
```

---

## 十、验证计划

```bash
# 端到端 smoke test
python scripts/preprocess.py --input data/test_logs.json --output outputs/preprocessed.json
python scripts/build_kg.py --config configs/config.yaml
python scripts/recall_entities.py
python scripts/rca_inference.py --config configs/config.yaml

# 评估
python scripts/evaluate.py --pred outputs/rca_results.jsonl --gold data/groundtruth.json

# Agent 模式
python src/graph.py --config configs/config.yaml --mode agent
```
