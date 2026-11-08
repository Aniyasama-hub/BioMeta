# 注释、出图与 BioMethod 修订记录

日期：2026-11-08。基于 `beb9139`，沿用 R Shiny、原生 JavaScript/CSS 与现有独立 R worker。没有迁移平台、数据库或分析任务架构。

## 对应本次八项需求

1. 删除 BioMethod 文章右侧篇内导航及占用的栏位。保留标题锚点、深层刷新、代码高亮、公式、参考文献和工作站互跳。
2. 目的通路颜色改为上下排列的独立控件。输入框标明六位 HEX，右侧实时显示色卡和实际颜色码；背景支持 `transparent`。格式错误有前端状态与后台校验。这两项作用于目的通路名称标签，不改变柱、气泡或热图矩阵的颜色。
3. 核对公共注释来源与人/小鼠缓存，增加统一元数据、只读本机信息接口和文章动态信息。扩写 GO/KEGG，新增 Reactome。全部八篇文章统一五个二级标题：定义解释、分析原理、分析操作、适用范围、参考与致谢。PCA 长文、代码、数学和原有细分段落保留。
4. 直接填写和上传名称表是同等、互斥的输入方式。只读取当前选中的方式；切换时保留另一种输入，防止丢失。旧无模式参数的脚本保留原自动兼容行为。
5. GO/KEGG 目的通路支持正式名称和稳定 ID，并提供本机注释库搜索、多选、加入输入框。选择保存稳定编号，直接输入仍识别正式名称；统一处理大小写、空白、分类前缀、KEGG `path:` 和物种尾注。不会作模糊名称替代。自动通路注释热图复用同样匹配规则。
6. KEGG 默认下载本次出图通路的官网参考机制 PNG，也可选所有符合结果阈值的通路或关闭。导出下载清单，含 URL、状态、哈希、缓存来源、获取时间和错误；部分图片失败不会丢失统计表，完成状态会提示未下载数量。重绘复用原机制图，不再次联网。
7. 公共 GO 可导出 BP/CC/MF 合并分面、单类图或二者；图型支持柱形、气泡或两种，柱形支持水平/竖直。每类独立取前 N 项；新建 GO 页面默认每类 5 项，原已保存步骤的数量仍保留。合并图保留三个面板，空类别明确说明；单类清单区分未选择与无结果。自建 GMT 若无 GO 分类信息，仍按普通基因集绘图，不编造 BP/CC/MF。
8. 四类通路分析均提供 P value、Adjusted P value、FDR（BH）及排序方向，GO/KEGG 另可按比例/数量，GSVA 可按 logFC 绝对值。上传 DEG 后展示实际数值列，可按显著性、变化幅度或两者筛选，允许不含 logFC 或不含 P 值的合法输入。

## 统计语义与导出

基因筛选和通路排序是两个阶段。上传 DEG 的显著性列、变化列和阈值由用户选定，记录于 `ora_input_selection.json`。涉及显著性筛选时，背景优先沿用有限原始 P 值确定的受检范围；没有原始 P 值时使用所选有效显著性列。仅变化幅度模式按有效变化值确定，不依赖未使用的 P 列；再与注释成员相交。候选集另外应用阈值与方向，不把 padj 缺失直接等同于未受检。背景、候选、编号映射仍各有独立 CSV。

本实现的通路 BH 调整值与 FDR（BH）使用同一结果列，界面明确显示同义关系。上传数据里名称不同的实际列仍可分别选择，不虚构统计量。ORA 不会因为用户选择了基因 logFC 就生成所谓“通路 logFC”；GSVA 的 logFC 则是评分比较的实际效应量。GSVA 启用行聚类时，排序先选择行，最终排列还受聚类影响。

GO 各分类分别检验并做 BH 调整，合并图只负责排版。作图层保持准备好的排序，清理显示标签不改原编号。目的通路标记不改变统计、排名或 Top N，也不会强行加入不显著条目；`target_pathway_matches.csv` 记录是否匹配和出图。修改分析选择须运行分析；单纯颜色、字号和方向等样式可重绘。

机制图文件为 `kegg_maps/kegg_<物种通路ID>_mechanism.png`，清单为 `kegg_map_downloads.csv`。它是官网原图，当前没有叠加实验表达量。默认仅下载出图通路；“全部符合阈值”模式可能耗时较长。网络请求只发送公共通路 ID，不提交表达矩阵或样本信息。按 [KEGG 官方接口](https://www.kegg.jp/kegg/rest/) 限制请求频率，并使用[官方 PNG 接口](https://www.kegg.jp/kegg/rest/keggapi.html)。

## 本机注释审查快照

下表是本轮读取既有本地缓存所得，获取时间为 2026-11-05；不是官网当前发行覆盖率比较，也没有强制替换旧缓存。四份缓存没有发现无效物种 ID、空名称或重复成员关系。

| 资源 / 物种 | 通路 | 基因 |
| --- | ---: | ---: |
| KEGG / 人 | 372 | 9451 |
| KEGG / 小鼠 | 368 | 11244 |
| Reactome / 人 | 2861 | 11470 |
| Reactome / 小鼠 | 1842 | 8801 |

GO 采用当前安装的 GO.db、org.Hs.eg.db / org.Mm.eg.db 和 AnnotationDbi，按本次输入生成映射，不把基因子集 GMT 冒充完整 GO 本体。分析导出实际包版本、注释来源元数据和 GMT 哈希。KEGG/Reactome 旧缓存未记录发行号的情况如实显示；获取时间和发行号不可互换。

元数据在 `shared/annotation-libraries.json`。`/api/knowledge/annotations` 和带 `annotation_libraries` 元数据的文章读取本机当前版本、质量与数量，避免文章写死版本号。该接口只读，不联网、不暴露研究数据和个人路径。名称查询同样只使用已有本地目录；未缓存的资源可先直接填写官网编号，或运行相应公共分析建立缓存。

## 主要文件与维护

| 范围 | 文件 |
| --- | --- |
| 实际列、筛选、排序和通路匹配 | `app/R/pathway_options.R`、`toolbox.R`、`annotated_heatmap.R` |
| ORA 统计、GO 图集合、GSVA/GSEA 排序 | `app/R/pathways.R`、`prepare.R`、`plots.R` |
| 机制图、注释追溯、执行与重绘 | `app/R/public_pathways.R`、`toolbox_analysis.R`、`toolbox_render.R` |
| 界面与 HEX 色卡 | `app/app.R`、`app/R/style_schema.R`、`app/www/settings-actions.js`、`themes.css` |
| 独立导出及 CLI 依赖 | `app/R/portable_export.R`、`app/run.R` |
| 知识接口、阅读布局 | `apps/biomethod/R/service.R`、`www/biomethod.js`、`www/biomethod.css` |
| 文章和元数据 | `content/biomethod/articles/*.md`、`catalog.json`、`scripts.json`、`references.json`、`ARTICLE_TEMPLATE.md` |
| 长期规范与上下文 | `AGENTS.md`、`BioMethod.agent`、`apps/biomethod/README.md` |

新增普通文章仍只需 Markdown 与 catalog 元数据。需要显示公共资源时填写 `annotation_libraries`；新增脚本关联仍登记实际文件/函数，不复制第二套代码。现在有 8 篇文章、9 个脚本、14 条参考资料。标题模板、前端校验和内容测试使用同一五段要求。

## 验证入口

`app/tests/pathway-review.R --with-kegg` 使用小型合成统计值与公共基因编号，检查仅显著性/仅变化列、互斥输入、实际 GO 三分类及横纵导出、重绘和机制图成功/失败清单，并真正下载分析所选通路的官网 PNG。未运行用户研究数据或完整 RNA-seq 建模。

`app/tests/annotation-review-ui.py` 覆盖八篇文章、无侧边目录、PCA 公式与深层刷新、注释接口、真实名称查询、实际列选择、通路名称/编号、输入方式切换、模板下载、HEX 即时反馈、真实 ORA 和 ZIP。原 `apps/biomethod/tests/reading-targets.py` 转入这一回归入口。

既有 `pathway-targets.R` 验证标记不改变统计、四种格式与独立脚本；`portable-exports.R go kegg gsea gsva` 检查四类工具的独立执行。公共 GO 图集合也在无 Shiny 的导出脚本中实际执行。另核对原始 P 值背景保留、GSVA 多指标排序、R/JS 语法、前端格式、知识内容关联及平台集成。测试产物、缓存、图像和数据继续被 Git 忽略。

本轮最终结果：以上分析、导出与浏览器检查均通过。浏览器未记录脚本错误；390px 下核对了 HEX 色卡和两个主题的横向宽度。知识内容图为 8 篇文章 / 9 个脚本 / 14 条资料，包含真实项目切换、刷新、前进后退、公式、搜索，以及在 BioMethod 中浏览时后台合成任务继续运行。Impeccable 对触及界面的静态扫描无发现，四个触及的 JS/CSS 文件通过 Prettier 3.6.2，R/JS 语法和 Git 空白检查通过。

GO 的结果预览优先显示 BP/CC/MF 合并图，再提供各类图选择。知识库旧测试中同目标链接可能同时出现在正文和自动生成的脚本/工具卡片，验收已使用明确的首条链接；文章数报告改为实际清单长度。没有为通过测试删除真实入口或压缩 PCA 正文。
