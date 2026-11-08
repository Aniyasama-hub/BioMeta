# biometa 命名、环境与 BW-D01 排查记录

日期：2026-11-09。基于提交 `119799f`。沿用 R Shiny、原生 JavaScript/CSS 和独立 R worker。项目正式显示名为 `biometa`；原目录 `BioWorkbench`、路由、历史任务、配置键和 BW 错误码保留兼容。BioMethod 的名称不变。

## 根因与复现证据

原始文件 `Batch_DEG_HA_CuPB_vs_M2_all.csv` 可访问，SHA256 为 `a06c706c036a46bb8b8a0be0d063d60b0f834ed6af316257e106bc994d5b244b`。实际检查为 18,531 行、486 行 Significant=TRUE、无重复 gene_id。没有改写原文件，也未重新拟合差异表达模型。

既有失败任务 `20261109-004832-file6e08297f` 的 status.json 和 job.log 记录了相同 BW-D01。修改前直接将完整原表传给旧 `tb_entrez_ids()`，复现完全相同的五个示例。移除名称列后旧函数得到 15,229 个映射；486 行显著子集不触发该错误（旧函数得到 467 个映射）。后二者仅用于定位，不能说明显著子集能提供完整背景。

旧调用链为：上传/本地路径 → `tb_launch_job` 保存输入快照 → `toolbox_worker.R` → `tb_prepare_deg` / `tb_resolve_gene_columns` → `tb_public_pathways` → `tb_entrez_ids` → `.run_ora` → GO BP/CC/MF 统计与绘图。物种由参数明确选择，不会根据文件名推断；该任务为 mouse，加载 org.Mm.eg.db。

旧 `tb_entrez_ids` 位于 `app/R/public_pathways.R`：先将 gene_id 按 Entrez、Ensembl 查询，缺失时回退 gene_name 的 SYMBOL 查询；再将每个 gene_name 单独按 SYMBOL 查询 Entrez。判断条件是两者均非 NA 且 Entrez ID 不等。只要任意一行满足就 stop，并只显示前 5 个例子。`tb_run_request` 把所有公共注释错误统一包装为 BW-D01，再给出含本地 GMT 的笼统建议。

真实触发条件不是 Symbol 字符串不相等，而是两次查询所得 Entrez 不等。问题在于：未查 ALIAS、未检查 Symbol 是否能反向指向另一稳定 ID、未区分未证实名称差异与可证实身份冲突；而且在候选基因筛选前对整张背景表阻断。背景映射本身应保留，修复不能改成只校验显著行。

## 五个原始示例的逐行诊断

下表来自本机实际查询。annotation_source 均为 `org.Mm.eg.db`，annotation_version 均为 `3.21.0`；resolved_id 是该 Ensembl ID 唯一对应的 Entrez ID。所有输入名称均原样保留。机器可读完整表见本机 `app/tests/_pathway-review/mapping-debug/five_gene_diagnostics.csv`。

| input_id | input_symbol | database_symbol | aliases | resolved_id | conflict_reason |
| --- | --- | --- | --- | --- | --- |
| ENSMUSG00000062382 | Ftl1-ps1 | Ftl1-ps2 | Ftl; Ftl-ps; Ftl1-ps2; Gm20746 | 434624 | name_difference_unconfirmed |
| ENSMUSG00000073538 | E330020D12Rik | Gm46246 | Gm46246 | 108167838 | name_difference_unconfirmed |
| ENSMUSG00000098055 | Gm26947 | Gm36750 | Gm36750 | 102640758 | name_difference_unconfirmed |
| ENSMUSG00000056592 | Zfp658 | Zfp175 | Zfp175; Zfp658 | 210104 | known_alias |
| ENSMUSG00000111713 | Gm20234 | Slfn10 | mFLJ00257; Slfn10; Slfn10-ps | 237887 | name_difference_unconfirmed |

旧 SYMBOL 查询分别返回 634386、626058、102640832、634762、102635154；这些记录在本机包中均没有反向 Ensembl ID。Zfp658 同时是 210104 的已知别名，因此允许继续并记录别名警告。其余四行没有本机别名证据，也没有足够的反向稳定编号证据证明跨基因；只能称“未证实的名称差异”，不能宣称已证实为历史改名。

另发现两个原先被“只显示前五个”遮蔽的差异：

| 输入 Ensembl / 名称 | 本机 ID 映射 | 名称的反向记录 |
| --- | --- | --- |
| ENSMUSG00000110018 / 5430437J10Rik | Entrez 100418252 / Gm20957 | Entrez 71432 / ENSMUSG00000121619 |
| ENSMUSG00000114515 / Aldoa | Entrez 129135233 / Gm57854 | Entrez 11674 / ENSMUSG00000030695 |

这两行在当前包内有明确的另一个稳定编号，均非显著。它们在严格模式下仍被阻断为 BW-M02；“非显著”不能作为忽略身份冲突的理由。此结论针对当前数据库版本，并不替代原始建库注释的人工核实。诊断清单见 `confirmed_conflicts.csv`。

## 修复后的映射与统计行为

- 新 `app/R/gene_mapping.R` 集中解析 ID、查询 SYMBOL/ALIAS/反向 Ensembl，并输出逐行原因。有效且唯一映射的 Ensembl 为身份主键；只去掉 Ensembl 的数字版本后缀，不改原文件和原导出编号。稳定 ID 未映射时不再用名称强行“救回”。
- 已知别名、没有足够反向证据的名称差异为 Warning。多个输入 ID 共用名称时保留各 ID，不按 Symbol 强行合并。一个稳定编号映射到多个 Entrez 时标为 ambiguous_id，不随机取第一个；未映射和多重映射保留完整报告，并明确从公共匹配中排除。
- 无效 Ensembl 格式或明显物种不匹配为 BW-M01；当前注释内可确认的跨基因差异为 BW-M02；没有可用映射/注释为 BW-M03；查询/数据库/下载故障为 BW-D02，不再冒充映射冲突。必需包缺失仍使用既有依赖错误类别。
- ORA 继续使用用户实际选定的显著性列、变化列、方向和阈值；背景按既有受检规则确定，再与实际注释成员相交。候选和背景执行相同的身份规则；没有改成仅对显著行映射。
- GSEA 使用全部有限有符号 stat，不应用 ORA 的显著性筛选。移除额外的“原始 P 必须有限”限制，避免有效 stat 被无关 P 缺失删除。公共 GMT 使用输入 gene_id 保留对应关系；Symbol GMT 原有确定性去重规则仍为绝对统计量优先，其后按 ID 排序。
- 重复原始编号继续在输入解析阶段报错；去掉 Ensembl 版本后缀后重复的稳定编号也阻断，避免一基因多版本行被重复计入统计。不同稳定编号仅共用显示名称时不强行合并。
- 参数中可明确选择“仅使用编号（确认后不使用名称校验）”。这等同于用户不提供辅助名称列，不改变原始 CSV；编号格式、物种、唯一映射等验证仍保留。默认是严格辅助校验，不自动替用户接受本次两处差异。

`public_gene_mapping.csv` 在身份检查中止前写出，包含用户要求的八列和候选 Entrez、Symbol 反向 Entrez/Ensembl、状态、重复名称标记、兼容旧列。空字段表示该数据库没有提供对应记录，不代表已查明历史沿革。`mapping_quality.json` 记录总数、成功比例、未映射/多重映射、别名/名称差异、确认冲突、注释覆盖、候选、背景、最终参与数，以及物种、包版本和实际源元数据。分析结果区可展开映射质量摘要，失败时也能查看。

原完整文件在严格模式下仍阻断两处 BW-M02，属于预期保护。对完整输入执行用户明确的 ID-only 模式后，成功映射 15,229 / 18,531（82.18%），其中未映射 3,208、多重映射 94；14,432 个输入基因有所选 GO 注释，797 个已映射基因缺少当前注释；按原阈值选中 486 个候选，最终有注释的富集候选为 436 个，背景为 14,432 个。不能将全部 486 个候选都宣称参与了最终检验。

## 注释版本、缓存与外部查询限制

实际环境为 R 4.5.1，org.Mm.eg.db 3.21.0、AnnotationDbi 1.70.0、GO.db 3.21.0。org.Mm.eg.db 元数据记录 Ensembl 来源日期 2024-Oct17，Entrez 来源日期 2025-Feb22，GO 来源日期 2025-02-06。版本差异客观存在，不能把包号/取用时间说成数据库最新版本。

当前 GO 映射只使用本地 OrgDb/GO.db，没有调用 biomaRt、MyGene 或远程 Ensembl，也没有混入在线补查结果。辅助向 Ensembl REST 查询这五个公共编号时均返回 HTTP 500，响应失败已如实保留；没有据此编造当前官方名称或历史沿革。自动分析不会依赖这次远程补查。KEGG/Reactome 缓存继续按物种隔离，并保留既有来源和取用时间；未强制更新、删除或把不同发行版合并。

自建 GMT 仍是可选来源，需确认来源物种和成员 ID 类型（gene_id/SYMBOL）；GMT 本身未必含物种元数据，不能自动保证兼容，也不能当作解决名称身份差异的通用补丁。公共参考按任务固定导出 GMT 与哈希。历史已完成结果不重算，重绘不改变统计。

参考：[AnnotationDbi 官方注释说明](https://bioconductor.org/packages/release/bioc/vignettes/AnnotationDbi/inst/doc/IntroToAnnotationPackages.pdf)、[GO 官方背景集说明](https://geneontology.org/docs/go-enrichment-analysis/)。生物学判断以本任务版本与原始注释核实为准。

## 环境与前端

`app/tools/find-runtimes.ps1` 在本机扫描已保存配置、当前 R、PATH、Windows 32/64 位用户/系统注册表、软件 App Paths、Program Files、用户安装目录、磁盘根部常见软件目录（有限深度）、Conda/虚拟环境和 Python 启动器。不会递归扫描整块磁盘的所有文件。R 的 bin 和 bin/x64 视为同一安装，虚拟环境和不同安装即使版本相同也保持独立。

R/Python 候选实际运行版本命令；RStudio 读取文件版本而不启动 GUI。探测/版本检查清理父 R 的 R_HOME/R_LIBS 等继承项，避免误用其他版本库。多个候选以版本、完整路径和来源列出，默认不勾选，需点击“使用所选环境”；取消保留原配置。存在待选候选时不允许保存。这里只确定所选环境，R 在下次启动生效，现有分析任务不被终止。

本机实测发现 R 4.5.1 和 4.6.1，以及四个可运行 Python 入口（包括相同版本的不同位置）。此列表是测试时的本机结果，不是硬编码的安装地址。自定义的深层目录仍可浏览/手动指定。独立脚本、图片排版标题和启动器显示名同步为 biometa。

暗色卡片不再把预览放在独立白色图片区，改成半透明实际图像位于名称背后。两主题、390px 宽度及图片加载已在浏览器检查，科研出图配色未改变。

## 失败任务诊断导出

任务记录的“导出日志”仅在 failed 状态启用，红色常亮；成功、运行中、排队和取消状态均为灰色禁用。后端同样校验任务属于本工作站且状态确为 failed，不能靠直接调用下载地址导出成功任务。

`app/R/job_diagnostics.R` 收集该任务已有的 inputs、参数和样式、状态、完整 job.log、结构化错误与堆栈、sessionInfo、脚本快照、部分输出和文件 SHA256 清单；不收集其他项目和全局环境变量。新任务在启动时保存执行脚本快照，worker 记录实际 R/包环境。诊断包包含研究输入，下载按钮说明其用途；保存在本地，不自动发送给任何服务。

旧失败任务若没有执行时的脚本/环境快照，README 明确注明缺失；当前代码另放 `current_source_NOT_original`，当前生成的独立复现入口另放 `replay_current`。不能把当前版本冒称旧任务实际执行版本，也不重写旧日志。若独立脚本生成失败，原始资料仍打包并记录生成错误。

## 验证结果

| 验证 | 结果与范围 |
| --- | --- |
| 原 CSV 旧映射复现 | 已复现相同 BW-D01，证据保存于忽略目录 before.json / 旧任务日志 |
| 原 CSV 修复后严格模式 | 按预期阻断两处 BW-M02；五个原始示例不再被误报为确认冲突 |
| 仅 Ensembl ID 的完整文件 | 实际 GO 分析成功；BP/CC/MF 合并及单类，柱形/气泡共 8 张 PNG |
| 完整原 CSV 主动 ID-only | 实际分析成功；与上一项完整 ORA 结果表一致 |
| 486 行显著子集 | 映射检查通过；未将其当作完整背景执行正式 ORA |
| 别名、共享名称、假基因、非编码、未映射、多重映射 | 已覆盖；稳定编号保留，歧义明确报告 |
| 真正跨基因、错误物种、格式、数据库查询失败 | 对应分级保持阻断；额外打开只读注释连接后将其关闭，验证无效连接返回 BW-D02，原数据库连接仍有效。不宣称此测试代表所有远程服务故障 |
| GO BP/CC/MF 与横纵、标记、机制图 | 既有 pathway-review.R --with-kegg 实际通过，含官网图片下载及失败清单 |
| 公共小鼠 KEGG / GO GSEA | 合成统计值的实际 worker 通过；350 个有限 stat 全部保留，ORA 不可能阈值不影响 GSEA |
| 独立 go/kegg/gsea/gsva R 脚本 | 四类实际执行通过 |
| 历史工作流核心 | workflow-v2-core.R 通过，测试夹具补齐新质量摘要的真实写入接口 |
| 前端实际浏览器 | 正式名称、两主题卡片、真实多环境选择、成功禁用/失败红色、实际诊断 ZIP、映射摘要、390px 宽度通过 |

分析测试只重新使用已生成的 DEG 表和公共编号/合成统计值，不运行 Count 建模，不修改输入、安装依赖或升级注释包。测试脚本为 `biometa-debug.R`（原文件路径为可选显式参数）、`biometa-public-pathways.R` 和 `biometa-ui.py`。所有原始数据、结果、截图、压缩包、完整诊断 CSV 与测试日志位于已有 Git 忽略范围，没有随源码提交。

最终 R、PowerShell、JavaScript 语法、触及 JS/CSS 的 Prettier 和 Git 空白检查通过。浏览器没有脚本错误。Impeccable 静态扫描仅提示既有图片排版 HTML 的暖色背景；本轮该文件只更新产品标题，按用户已确认的亮色风格保留配色，没有把这项旧设计当作本轮错误改写。

## 文件与剩余限制

主要实现：`gene_mapping.R`、`public_pathways.R`、`pathways.R`、`toolbox_analysis.R`、`toolbox.R`、`portable_export.R`、`job_diagnostics.R`、`toolbox_worker.R`；界面：`app.R`、`settings_tools.R`、`settings_ui.R`、`workbench_settings.R`、`find-runtimes.ps1`、`themes.css`；命名：`shared/platform.json`、`shared/www/platform.js`、启动器/页面标题与当前设计文档。

当前注释包的未映射和多重映射仍存在；不擅自下载另一个版本去混合填补。两处可确认的版本内差异仍需用户根据原注释核实；保留严格模式和明确 ID-only 选择。远程 Ensembl 查询失败仍未解决，生产映射不依赖它。深层自定义运行环境不保证自动发现，可浏览指定。历史任务缺失的执行快照无法补造。BW 代码、旧目录和历史结果不因改名而迁移。
