# BioMethod (Alpha) 第一版交付与验收

日期：2026-11-08。项目：BioWorkbench。分支：`codex/biomethod-alpha`。

## 架构检查与选择

现有工程是 R Shiny + 原生 JavaScript/CSS，R worker 由 processx 独立执行，计算和绘图分离；使用 CSV/RDS/JSON 与本地文件目录，启动器为 Start.cmd → launch.ps1 → app/start.R。已有分析/绘图包括 PCA、DEG、火山图、热图、GO、KEGG、GSEA、GSVA、PPI、免疫评分及通用绘图、组图；核心实现仍位于 app/R 与 legacy，未迁移到新框架。

选择单服务下的独立知识模块，而非引入 npm Monorepo、多端口或数据库。`app/app.R` 只增加平台壳、路由分发、静态资源与功能跳转。知识业务位于 `apps/biomethod`，内容位于 `content/biomethod`，公共配置与导航位于 `shared`。原分析算法、阈值、输入输出和 worker 运行代码没有修改。`app/R/toolbox.R` 仅把 markdown 加入依赖报告。

主要兼容点是 Shiny 的相对依赖资源、WebSocket 和动态绑定。页面模板把 base 放在依赖资源之前；WebSocket 锚定当前本机服务根路径；项目切换保留工作站容器和连接。目录边界支持未来拆出知识服务，但仍需届时配置独立托管和路由。

## 交付内容

- Logo 项目菜单，当前选中状态、键盘展开与独立首页。
- `/workstation`、`/biomethod`、分类、文章、脚本和文献详情路由；浏览器刷新、前进与后退。
- 知识独立布局，沿用 night、verdant、classic 三主题；知识页设置按钮连接原设置。
- 四个知识板块、全局搜索、学习路线、推荐教程、最近更新。
- Markdown、R 高亮、LaTeX 展示公式、图片、目录、站内链接及加载/空结果/错误/重试状态。
- 七篇人工维护样板；PCA 完整教程含公式、教学代码、原工作站预览图、结果解读与真实脚本。
- Bulk 的输入—建模—功能解释—交付流程图，标明逐步审核。
- 八项真实源码映射及 SHA-256，不复制执行脚本；八条可核实原始论文/官方资料。
- 功能 ID 映射实现工作站与教程双向导航；未覆盖教程的工具保留原有帮助。
- Alpha 由 `shared/platform.json` 一处配置；新增文章仅修改内容与元数据。
- 视频元数据 Schema 与只读接口；前端没有视频入口、列表、卡片或播放器。

## 验收结果

测试环境：Windows、R 4.5.1、Shiny 1.14.0、markdown 2.0、digest 0.6.37，Python Playwright/Chromium；专用本机端口 7898。

| 检查 | 结果与范围 |
| --- | --- |
| Logo 菜单与项目切换 | 通过；两项目选中状态、鼠标、键盘 Enter |
| 独立页面及 Alpha | 通过；配置生成名称与完整独立布局 |
| 分类与搜索 | 通过；四分类、正文/脚本/文献搜索、空结果及用户搜索内容不作为 HTML 执行 |
| 文章渲染 | 通过；七篇 API，PCA 四组公式、R 高亮、图片、九段正文及目录 |
| 路由与刷新 | 通过；直接打开与刷新深层 PCA 地址、前进/后退、站内跳转 |
| 真实脚本 | 通过；八条映射，接口 hash 与原文件字节一致，输入输出/参数/依赖/错误可读 |
| 双向跳转 | 通过；PCA 分析标题问号进入教程，教程返回真实 PCA 参数页 |
| 分析连续性 | 通过；内置合成 KEGG 启动后切换知识库再后退，WebSocket 数量不增加，后台 status.json 为 completed |
| 原工作站回归 | 通过；21 个导航、三主题与持久化、提示描述、合成 KEGG 校验/提交/锁定/取消/完成/ZIP/重绘 |
| 视频预留 | 通过；items 为空，Schema 可读，页面无视频 UI |
| 内容与访问边界 | 通过；ID/引用/功能/脚本关联一致，未知资源 404；未注册脚本不可读，shared R 不作为静态资源公开 |
| 只读接口 | 通过；业务单测写请求 405；本机 httpuv 在业务层前将非 GET 拦截为 400，不产生写入 |
| 三主题与窄屏 | 通过；知识页设置应用三主题、390px 首页/文章/脚本无横向溢出，设置弹窗及遮罩确实关闭 |
| 语法与格式 | 通过；R parse、node --check、Prettier 3.6.2、git diff --check |
| 设计检查 | 手动查看桌面/手机与主题截图，新增代码 Impeccable detect 返回空结果；不代表全站可访问性认证 |
| JavaScript 控制台 | 两套浏览器测试均无 pageerror |

运行命令与维护说明见 `apps/biomethod/README.md`。本项目没有 npm 前端构建步骤；已验证实际 Shiny 服务启动及页面资源加载。静态公式与高亮库为本地固定版本，原许可证与包完整性记录保留。

首轮发现的深层刷新依赖路径问题已修复。验收最初依赖本机已保存示例选择，现已明确通过设置选择 synthetic；未读取用户研究数据。截图测试已补上弹窗和遮罩关闭状态等待，避免把过渡状态当作最终页面。

## 新增及修改文件

修改：

- `app/app.R`：平台壳、Logo 菜单、知识路由、静态资源和功能跳转。
- `app/R/toolbox.R`、`app/tools/dependencies.R`：增加 markdown 依赖检查。
- `README.md`：统一入口、目录边界与知识库说明。
- `app/THIRD_PARTY_NOTICES.md`：离线阅读库许可。
- `.prettierignore`：排除新增第三方库。

新增：

- `shared/platform.json`、`shared/feature-map.json`、`shared/platform.R`。
- `shared/www/platform.js`、`shared/www/platform.css`。
- `apps/biomethod/R/service.R`。
- `apps/biomethod/www/biomethod.js`、`apps/biomethod/www/biomethod.css`。
- `apps/biomethod/www/figures/pca-example.png`、`bulk-workflow.svg`。
- `apps/biomethod/www/vendor/katex/`：0.16.22 浏览器资源、字体、LICENSE、SOURCE.json。
- `apps/biomethod/www/vendor/highlight/`：11.11.1 core/R/主题、LICENSE、SOURCE.json。
- `apps/biomethod/tests/content.R`、`integration.py`。
- `apps/biomethod/README.md`。
- `content/biomethod/catalog.json`、`scripts.json`、`references.json`、`videos.json`、`video.schema.json`。
- `content/biomethod/articles/bulk-rnaseq.md`、`normalization.md`、`pca.md`、`deg.md`、`go-kegg.md`、`gsea.md`、`limma.md`。
- 本交付记录。

科研输入、个人设置、任务缓存、生成结果和浏览器截图不提交到 Git。本轮测试默认示例为 synthetic，界面主题恢复 night。

## 内容维护与后续边界

文章通过 Markdown + JSON 唯一 ID 维护；脚本关联只配置真实路径和函数，文献应先核实再登记，具体字段和命令见独立 README。视频未来扩展位置为 `content/biomethod/videos.json`、`video.schema.json` 与 `/api/knowledge/videos`，尚无上传或播放服务。

尚未实现：完整英文内容/语言切换、CMS、账号权限、其他组学教材与视频前端；这些不属于第一版要求。现有 translations 与项目注册为扩展预留，新增第三个子项目仍需实现自己的页面及路由适配。反向代理子路径与独立部署需要调整根路径资源和 WebSocket 配置。

只验证内置合成 KEGG 到后台任务的实际链路，没有重跑全部真实人/鼠流程，也没有运行用户科研数据。启动时可见 Shiny 包构建于 R 4.5.3、当前运行 R 4.5.1 的已有提示，本轮启动和验收均成功，未更新 R 环境。

当前工具环境未提供创建新聊天窗口的接口，因此没有另开 Codex 聊天；独立子项目目录、页面与浏览器路由已经交付。
