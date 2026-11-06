# Cytoscape 参考记录

本机 Cytoscape 3.10.3 的样式编辑 JAR 包含视觉属性编辑器、默认样式载入和样式应用动作。REA 证据 `ev_35ba47376dd8f63f6422f466a67f454f2bb7caa4f34480f0e952296bbe4b6e84`。

本机 MCODE 2.0.3 插件 JAR 包含算法模型、群集结果面板和创建群集网络视图任务。REA 证据 `ev_cc509b950c173bc5560f10476bea5a9e49aa892f4046ccd029ae44eca3bf11f2`。

工作站借鉴将样式与群集结果分开的操作方式。它用 Cytoscape.js 编辑画布和节点，使用 R igraph 计算 Louvain、Walktrap、快速贪婪和连通分量，之后在浏览器按大小或密度等指标筛选群集。这些算法有各自的分群依据，结果与 MCODE 不要求一致。 [Cytoscape 样式文档](https://manual.cytoscape.org/en/stable/Styles.html) · [clusterMaker2](https://apps.cytoscape.org/apps/clusterMaker2)
