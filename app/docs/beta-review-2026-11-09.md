# 0.2.0-beta.1 最终复检报告

**结论：本轮约定的 14 个回归套件全部通过，最终失败数为 0。** 另通过依赖、语法与 PPI 指标检查。此前 Alpha 报告中的未通过项已逐项闭环；本报告不把新机器安装、其他操作系统或任意科研数据都描述成已验证。

biometa (Beta) 与 BioMethod (Beta) 共享 `shared/platform.json` 的版本 `0.2.0-beta.1` 和各自 `stage=Beta`。修改版本阶段没有更改统计模型中的 alpha 参数。发布仍待用户审阅，尚未推送 GitHub 或创建远程标签。

## 修复与适配

1. **组图状态丢失，修复产品代码**：图片数变化会重建上传控件，旧实现优先取流程 spec 的空图片路径，覆盖已选择的缓存。异步 updateTextInput 又可能早于新控件绑定。现在图片排版的初始路径优先取当前缓存，其余工具仍使用原规则。实际完整流程验证了两张不同标星图均有缩略图、路径正确、置顶和拖动后顺序正确；不靠延长缩略图等待时间通过。
2. **综合分析输入夹具**：Count 路径移除无关的处理后矩阵，并明确 downstream_input=FALSE、pathway_source=custom。既有脚本会因矩阵非空切换处理后输入，这才导致旧夹具缺 DEG/VST。没有放宽生产输入校验，也没有把失败工具从清单删除。15 条综合任务全部重新执行通过。
3. **知识库交互断言**：PCA 介绍帖只检验原理、公式、图像和技术帖入口；通过真正进入 pca-code 技术帖检查代码高亮，再跳到真实脚本来源，继续验证返回/前进。文章数和 Beta 标识与现行配置一致，18 篇文章都保留检查。
4. **流程测试的必选项**：首次开始及刷新后重新开始均显式选择科研配色，保留“必选”的产品约束。补齐后完整测试通过到 ZIP、编辑器和预设恢复。
5. **主题测试就绪条件**：测试主动选择自己的起始主题，示例切换后等待 Shiny 空闲再检查输入，并在失败时打印真实通知。保留所有 21 个入口、取消、真实执行、锁定、下载和重绘检查；不强制触发隐藏按钮或跳过错误。
6. **其他已修复项保留回归**：36 图四格式断言、真实 jobs 层级的导出夹具、DEG 饼图遵循所选格式均再次通过。错误映射、错误物种和失效数据库仍按预期被拒绝。

## 最终结果

| 套件 | 最终结果 | 实际覆盖 |
| --- | --- | --- |
| integration.R | 通过 | 15 条合成 Count/矩阵综合任务，SVG 单格式，不强制 PNG |
| portable-exports.R | 通过 | 22 个独立 R 示例脚本，全部实际执行；各目录实际产生 PNG |
| smoke.R | 通过 | 9 条绘图分支 × 4 格式，共 36 个非空文件 |
| workstation-updates.R | 通过 | 九套示例一致性、来源/默认 DEG、导出命名、样式和功能说明 |
| workflow-v2-core.R | 通过 | 流程实例、配置与持久化核心规则 |
| biometa-debug.R | 通过 | ENSA、别名、确认冲突、共享名称、假基因/非编码、未映射、物种/格式、版本重复、失效数据库连接和完整排序 |
| deg-formats.R | 通过 | 只选 SVG/PDF 时确有两种输出且没有额外 PNG |
| biometa-public-pathways.R | 通过 | 公共小鼠 KEGG ORA 和 GO GSEA，完整有限 stat 不套用 ORA 阈值 |
| BioMethod content.R | 通过 | 18 篇文章、9 个源码索引、15 条资料，教学与介绍分离、真实 GMT 示例 |
| workflow-v2-ui.py | 通过 | 自定义计划、返回/重跑失效、当前环节选图、两张标星自动填入、缩略图、排序、画廊筛选、完整流程 ZIP、编辑器撤销/重做、刷新恢复预设 |
| BioMethod integration.py | 通过 | 真实项目菜单/路由、刷新/前进后退、知识与分析互跳、后台 KEGG 在同一连接中继续执行、搜索/错误页/主题及移动布局 |
| ui-themes.py | 通过 | 双主题、21 个工具入口、示例切换、输入检查、运行/取消/重跑、重复提交锁定、ZIP 和重绘 |
| BioMethod editorial-ui.py | 通过 | 全部文章、独立代码教学、流程图/公式、深层刷新、两个真实下载、移动端和双主题 |
| biometa-ui.py | 通过 | Beta 标识、卡片预览、多版本环境选择、失败红色/成功禁用、真实诊断 ZIP、映射摘要与移动端 |

以上 14 个套件最终进程退出码均为 0。`workflow.log` 保留第一轮在刷新后漏选配色的失败，修正后的完整通过记录为 `workflow-final.log`，没有把旧失败日志覆盖成成功。机器汇总为本机 `app/tests/_pathway-review/beta-audit/final-summary.json`。

额外检查：PPI 合成图的算法指标/缺失标签/独立页面通过；30 个依赖包检查通过；全部 app/R 源码、主界面和 bootstrap 的 R 语法解析通过；7 个自有 JS 文件 node --check、4 个修改的 Python 测试语法检查及 Git 空白检查通过。两个项目后缀均实际显示 Beta。

## 环境与证据

Windows、R 4.5.1、当前已安装依赖。隔离目录从 Git 管理文件复制，不复制用户设置、研究数据或个人任务。公共注释测试沿用本机已有公开缓存，计算测试使用内置示例、160 基因/6 样本合成 Count，以及公共编号配合合成统计量；本轮没有重拟合用户研究 Count，没有升级包。

本地证据目录为 `app/tests/_pathway-review/beta-audit/`。主要日志为 integration.log、portable.log、各 R 套件同名日志、platform.log、themes.log、workflow-final.log、editorial.log、diagnostics-ui.log；浏览器截图与实际下载位于 browser/ 和测试脚本各自的忽略目录。诊断 UI 特意生成一项可信冲突失败任务，用于验证错误、报告与 ZIP；“全绿”指断言全部满足，不是关闭错误保护使所有输入都成功。

可复查入口（在隔离副本中启动 7898 服务后运行 Python，避免改变个人设置）：

```powershell
Rscript app/tests/integration.R app
Rscript app/tests/portable-exports.R
Rscript app/tests/smoke.R app
Rscript app/tests/workstation-updates.R app
Rscript app/tests/workflow-v2-core.R
Rscript app/tests/biometa-debug.R
Rscript app/tests/deg-formats.R
Rscript app/tests/biometa-public-pathways.R
Rscript apps/biomethod/tests/content.R
python app/tests/workflow-v2-ui.py --output app/tests/_browser/workflow
python apps/biomethod/tests/integration.py --output app/tests/_browser/platform
python app/tests/ui-themes.py --output app/tests/_browser/themes
python apps/biomethod/tests/editorial-ui.py --url http://127.0.0.1:7898
```

日志导出 UI 测试需先创建一项本机合成的确认冲突失败任务；本轮没有复制用户失败任务来填充夹具。脚本默认地址和真实环境候选依赖本机 Windows，不能直接当作通用 CI 配置。

## 边界与交付

没有在全新 Windows 上实际联网安装所有 R 包，没有验证其他 R 版本、所有浏览器、反向代理或跨平台部署；九套 GEO 数据检查了输入/默认 DEG 一致性，没有全部重新做差异建模。“全绿”仅对应上述完整列明的回归范围，不代表所有研究设计的科学结论都已审阅。

候选版本使用 Beta 标签，结构、安装和更新说明同步至 ARCHITECTURE.md、INSTALL.md、RELEASE_NOTES_v0.2.0-beta.1.md。候选 ZIP 从受控 Git 快照生成，检查不包含 results、研究输入、运行缓存、测试产物、个人设置和本机快捷方式；不捆绑 R。更新包及校验和供本地审阅，GitHub 上传继续等待用户确认。
