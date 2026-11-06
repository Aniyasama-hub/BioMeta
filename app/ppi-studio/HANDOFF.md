# 新对话交接 · PPI Studio

目标是继续优化独立的 PPI Studio。主工作站仅保留网络分析与基础编辑入口，用户通过「精细编辑」打开大窗口。讨论与修改默认在本地完成。用户的未发表数据不可用于开发、测试、报告或上传。所有验证使用合成网络或仓库内的合成示例。搜索代码时排除工作站的 `data/`、`app/results/`、日志和缓存。

## 已有需求与实现

- 用户最初要求参考本机 Cytoscape 3.10.3 的样式编辑和插件分群体验。REA 检查了本机样式编辑 JAR 和 MCODE 2.0.3 插件 JAR。证据及边界记录在 [Cytoscape 参考记录](../docs/cytoscape-reference.md)。
- 任务既支持分开上传 Node 和 Edge，也支持从 Count 模型筛选 DEG 后载入本地边表。网络数据经 ID 匹配、边分数单位转换、去重和阈值过滤后进入编辑器。保留孤立节点，输出节点表、边表和矩阵。
- 基础页面 `network.html` 和高级页面 `ppi-studio.html` 离线运行，共用本地 Cytoscape.js 与许可证。页面由 [network_import.R](../R/network_import.R) 生成。`template.html`、`editor.js`、`advanced.html`、`analysis.js` 和 `methods.js` 位于本目录。
- 基础页面包含画布宽高、布局、节点形状与大小、填色、选中节点或可见节点编辑、标签和 PNG 导出。独立窗将控件与画布分区，可分别滚动。精细编辑从任务保存的网络与样式启动。
- 标签曾因初始只显示前若干节点，以及将字段映射作为样式值传入而不能正确切换。现在使用逐节点的 `visibleLabel`，支持全部显示与全部隐藏，空名称回退为节点 ID。应保留这一行为。
- 已有 6 种节点风格与 8 套配色。配色显示节点、背景和边的色条与色值。点击「？」可查看算法公式、用途、范围与文献。
- 群集算法为连通分量、Louvain、Leiden、Walktrap、快速贪婪、标签传播、Infomap。排序支持节点数、边数和密度，前 N 群集仅保留群集内边。
- 枢纽指标为 Degree、NCC、MNC、DMNC、MCC、局部聚类系数、核数、加权 PageRank、介数、调和中心性。NCC 是邻域平均度，MCC 是极大团中心性，二者分别实现。高成本方法的图规模限制见 [README](README.md)。
- [metrics.R](metrics.R) 基于 igraph 计算网络结构。输出 `ppi_communities.csv` 与 `ppi_hub_scores.csv`。本次工作站改造将拓扑结果保存在本地绘图缓存中，仅重绘时可直接复用。

## 验证与边界

前次合成网络验证覆盖弹窗、标签从初始 1 个切换到 5 个和 0 个、空名称回退、色尺、NCC 前 2 节点和 Leiden 前 1 群集。正常后台入口也已生成两个编辑页和 PNG。复查可运行 [ppi-studio.R](../tests/ppi-studio.R)。旧任务必须重新运行才会生成当前编辑器。

可在新对话中读取本文件和所链接的源码后再按用户新要求修改。历史 GitHub 提交曾保留研究相关线索，未经用户明确授权不要上传或更改远端。
