# 系统设置与 Bulk 流程修改验收

日期：2026-11-08。使用内置合成数据，不运行个人研究数据，不实际批量更新软件包。

## 系统设置

工作空间只显示当前路径，并通过“浏览选择工作文件夹”调用 Windows 原生目录选择器；移除路径手动粘贴、进入子目录和上一级。选择后仍需“应用工作空间”，原自动识别输入逻辑保留。

主题只保留“黑夜”(night) 和“亮色”(classic)，旧 verdant 设置读取时迁移到 night。亮色首页复用既有免疫细胞/囊泡艺术组织图，以纸色 screen 混合融入浅色背景；图片是装饰插画，不是实验显微图，也不改变科研出图。

R、Python、RStudio 各提供自动嗅探、浏览和手动输入入口。检查按钮执行实际 Rscript/Python 查询版本，RStudio 核验可执行文件位置；Bioconductor 展示官网地址与所选 R 内的发行版本，不伪装成可执行程序目录。第一次未配置 R 且未通过命令行显式指定时，启动器先要求选择 Rscript.exe，验证版本并记录后再启动。R 地址切换下次启动生效。

目录/文件选择器位于 app/tools/pick-local.ps1，由 app/R/settings_tools.R 调用。使用 Windows STA/WinForms，仅对此项目选择器进程使用 ExecutionPolicy Bypass，不修改系统策略；UTF-8/BOM 与输出编码处理中文路径。自动化验收没有操纵原生 Windows 对话框，实际浏览/取消及第一次启动选 R 的窗口仍需在桌面手动点选确认；PowerShell 语法与 R 自动发现已检查。

通用合成示例改成三段说明，解释用途、配套文件与真实 GEO 示例的区别。九套来源 README 不改写，通过展示层把连续项目/表格行合并为段落，保留标题和原信息，不把整篇压成一段。

## 软件包管理

移除多选包安装框。按钮为“一键检测”“一键更新”，表格列为包名、当前版本、最新版本、功能简介、包对应网址、操作。查到更新的行显示“更新包”；无需更新灰色，查不到仓库版本单独提示，不能冒充最新。

app/tools/package-manager.R 在已配置 R 的独立进程里读取已安装非基础包（包含推荐包）、当前版本及 BiocManager 对应仓库 available.packages，生成真实报告。最新指与当前 R/Bioconductor 发行版相容的仓库版本，不强行升级 R 或 Bioconductor 大版本。基础包随 R 管理。

一键更新可以先自动查询，再更新所有检测到过期的包；单包按钮只更新对应包。更新写入独立准备库，按所选 R 的实际版本隔离，完成后再次查询；校验失败不切换现有库配置，日志显示失败。启用新库后重启工作站加载新版。在分析、检测或更新期间禁止重入包管理任务。更新完成再检测的逻辑已实现，但本轮未实际安装/升级包，以免变更现有环境。

已实际验证：R 自动发现与版本 4.5.1 检查；独立脚本只读仓库查询；界面按钮→脚本→版本表格，列名、灰色禁用按钮及动态反馈。网络不可用时应看错误与日志，不能把未知版本当作最新。

官方实现依据：https://bioconductor.github.io/BiocManager/reference/install.html 、https://bioconductor.github.io/BiocManager/reference/repositories.html 。

## Bulk 流程

每一步都先打开原有参数/样式面板，等待用户点击“运行当前工具”。移除原 open_bulk_step 中自动提交逻辑；下一步只进入下一步参数页。修复跨步骤把无关默认参数写回流程、覆盖 GMT gene_id/source 等配置的问题；修改当前可见参数才同步流程参数。

DEG 在原完整结果及筛选表之外生成 deg_summary.csv、deg_proportions_plot_data.csv、deg_proportions.png。汇总包括过滤前输入基因数、受检基因数、显著上调/下调/不显著数量；显著性和幅度阈值沿用用户设置。汇总同时计算两个方向，不受下游只看上调/下调选项影响。饼图以受检基因作为分母，未进入模型的低表达基因不混入不显著类别；受检但无法给出有限显著性的条目计入未达显著组。三类总数等于受检总数。

缓存位于 app/results/toolbox/bulk-cache 下的会话专属目录，每步完成自动复制 PNG；修改样式重跑产生的新任务图片也进入缓存。流程开始前、离开流程或会话结束会清空自身缓存，原任务及其输出仍保留在任务记录。切换到 BioMethod 也视为离开流程；不会因此停止已提交的后台任务。离开后不保留旧流程选图状态，下一次需新建流程。

下一步弹窗平铺已产生图片，可按分析步骤筛选、只看感兴趣、按文件大小排序。白色描边五角星表示未标记，点击图片填充黄色；完成选择后进入下一步。最终组图保留本地上传/拖拽与参数，新增“从本次自动化流程挑选”；选图直接填入该面板，不依赖事先下载。

PPI 基本与独立精细编辑窗口增加“加入本次流程缓存”。精细窗口保留 opener=null，通过按任务资源前缀区分的同源 BroadcastChannel 回传到嵌入编辑器，再到当前 Shiny 会话；服务端检查 PNG 格式和大小，在 network 步骤接收并默认标星。需要保持本次流程主窗口；独立离线导出的编辑器不是当前流程会话。

最终组图完成提供全流程 ZIP，文件名为项目_年月日时分秒.zip。01_pca 至 10_figure_layout 下保留完整任务目录，包括 inputs、outputs、日志、参数、状态与复现文件；09_network/edited 保存回传的编辑 PNG。workflow.json 记录跳过原因和星标图片信息。该包含输入快照，下载后的分享范围由用户决定；不会作为源码提交。

## 实际检查

- R 语法、JavaScript 语法、PowerShell 语法、Prettier 3.6.2、git diff --check 通过。
- app/tests/settings-bulk-review.py：设置项、两主题、R probe、十步真实合成流程，确认每步无自动启动；DEG 数量关系与 PNG、缓存/星标、独立精细窗口回传、缓存组图、步骤 ZIP、退出缓存清空、包检测表格通过，pageerror 为空。
- app/tests/ui-themes.py：21 导航、黑夜/亮色、设置持久化、合成 KEGG 校验/提交/取消/完成/下载/重绘通过。
- apps/biomethod/tests/integration.py：知识 API、文章公式/代码/图片、搜索、刷新/前后退、双向链接、同一 WebSocket 的独立合成 KEGG、两主题和窄屏通过。
- apps/biomethod/tests/content.R：内容关联和真实脚本映射通过。
- app/tests/settings-bulk-core.R 用独立临时合成文件验证全量打包 helper，确认输出、日志与输入快照都在包内。
- 新增前端 Impeccable detect 为空；保留用户确认风格，未升级旧产品记录 schema。

浏览器测试命令：python app/tests/settings-bulk-review.py --url http://127.0.0.1:7898 --output app/tests/_browser/settings-bulk 。仅按改动需要运行；该测试使用合成任务，设置最终恢复黑夜。测试截图、任务、版本报告均不加入 Git。

## 主要改动文件

app/app.R；app/R/settings_ui.R、settings_tools.R、workbench_settings.R、bulk_workflow.R、toolbox_analysis.R；app/tools/pick-local.ps1、package-manager.R；launch.ps1；app/www/settings-actions.js、themes.css、workbench-ui.js；app/ppi-studio/template.html、editor.js；app/examples/README.md；shared/www/platform.js；三个相关浏览器测试；DESIGN.md、PRODUCT.md、BioMethod.agent 与 BioMethod README 的当前约定。

后续维护检查：所选 R 的包管理进程清除继承自其他 R 的库搜索变量，使用该 R 自己的默认库及版本匹配的专用库；设置检测也按该可执行文件的真实 R 版本决定更新库目录。
