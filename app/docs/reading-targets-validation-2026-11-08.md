# 目的通路标记与 BioMethod 阅读修订

## 使用变化

- 图形样式面板删除“如何选择配色与来源”，保留科研预设、自定义色尺和已保存配色。
- GO、KEGG、GSVA 参数区新增“目的通路”：逐行输入名称/ID，或上传单列 CSV/TSV/TXT/XLSX，旁边可下载含 `pathway_name` 表头的示例 CSV。文本与表格合并后去重。样例随所选库变化，正式使用应替换为当前库的正式名称或稳定 ID。
- 目的通路仅做标记，不改变检验、阈值、排序或强制进入前 N 条。旧的 `pathway_terms` 仍是独立的高级出图限定，前端已明确标为“限定出图条目 ID”。
- 按名称或 ID 进行不区分大小写的精确匹配，保留名称中的空格；忽略显示层的 GO/KEGG 来源标记及 KEGG 人/小鼠标准物种后缀，不做模糊猜测。
- 图中的目的通路名称默认红色，图形样式的“目的通路标记”可修改文字及背景颜色，背景默认 `transparent`。GO/KEGG 支持气泡图和横/竖柱图标签；GSVA 支持热图行名，并与行排序、反转和名称换行同步。
- 完整结果 CSV 增加 `target_pathway`；`target_pathway_matches.csv` 分别记录请求、匹配 ID/名称、是否在完整结果内、是否在当前图中。标记与匹配报告也保留在独立 R 导出中。独立工具和 Bulk 阶段共用这套逻辑。

## 文章结构与写作

七篇现有文章统一为五个二级标题：概念、原理、分析流程、适用场景、参考文献。脚本、读图、常见问题和功能入口置于分析流程下；自动脚本与文献模块使用三级标题归入对应章节，不再产生重复的主章节。

PCA 正文约 1.5 万字符（含公式与代码），解释矩阵方向、Count/VST/缩放、高变基因、中心化、SVD、得分与负荷、解释方差、维度限制、离群点、批次与置信区域；配有手算示意、完整操作顺序和已有 VST 表的教学 R 代码。其他六篇本轮调整结构、保留已有内容，后续扩写应遵循 PCA 的详细程度和 `content/biomethod/ARTICLE_TEMPLATE.md`。前端和内容检查均核对主章节顺序。

新增 R `prcomp` 官方参考记录，实际核对 DESeq2 论文与官方教程；未将未重新核对的旧记录改为当天。PCA 示例图与数字例子仍明确标为教学示意，不冒充当前用户结果。

## 目录修复

根 `<base href="/">` 用于保证 Shiny 深层页面正确加载资源，但使裸 `#id` 被浏览器解析到站点根。目录现在生成当前文章完整路径加 hash；公共导航拦截同页锚点，只修改当前文章 hash、滚动和焦点。直接打开、刷新或后退到带 hash 的文章时，在正文挂载后定位目标。保持工作站容器和 Shiny 连接。长文目录可在视口内滚动，并区分主章节与子标题。

## 本轮验证

仅用合成输入，没有运行用户科研数据，也没有中断现有 7878 服务。浏览器使用专用 7898 服务。

- 内容图检查：7 篇文章、8 项真实脚本、9 条文献，全部通过；PCA 两段教学代码可解析，手算例子的首主成分解释方差与计算一致。
- GO/KEGG/GSVA：文本+表格匹配、未匹配记录、前 N 条外的目标、PNG/SVG/TIFF/PDF、标签颜色与背景、统计值不变、实际独立 R 导出执行通过。
- 额外检查 KEGG 带物种后缀的名称匹配及 Bulk 参数/输入继承。
- 浏览器逐篇检查五主章节和目录跳转；PCA 公式无 KaTeX 错误，目录点击不新增 WebSocket，深层 hash 刷新/后退、390px 宽度检查通过。
- 三种工具的目标输入、上传、示例下载、样式控件检查通过；GO 前端到真实 worker 的合成链路通过。页面无 pageerror。
- 暗色新控件、上传移除按钮及长文目录已审阅截图；语法与 diff 检查通过。

```powershell
$env:LC_ALL='English_United States.utf8'
& 'D:\R\R-4.5.1\bin\x64\Rscript.exe' --vanilla apps/biomethod/tests/content.R
& 'D:\R\R-4.5.1\bin\x64\Rscript.exe' --vanilla app/tests/pathway-targets.R
# 先启动专用 Shiny 7898；不更改用户主题/默认示例/保存设置
python apps/biomethod/tests/reading-targets.py
node --check apps/biomethod/www/biomethod.js
node --check shared/www/platform.js
```

产物在已忽略的 `app/tests/_enhancements/`。本轮没有重新覆盖全部公共库在线下载或全部真实人/鼠数据；统计计算继续使用既有模块。
