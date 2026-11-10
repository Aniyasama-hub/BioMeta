# BioMethod (Beta)

Bioinformatics Methods & Knowledge Hub：与生信分析工作站并列的独立知识子项目。通过原项目 `Start.cmd` 启动，访问 `/biomethod`。不需要 Node 构建、数据库或额外服务；继续使用已有 R Shiny、jsonlite、markdown、digest 与本地静态资源。

## 模块边界与架构

```text
BioWorkbench/
  app/                         原工作站与 R worker，保留原有位置
  apps/biomethod/
    R/service.R                独立只读知识服务
    www/                       独立页面逻辑、样式及离线公式/高亮资源
    tests/integration.py       API、页面及真实合成任务切换验收
    tests/content.R            元数据、引用、脚本与路由一致性检查
  shared/
    platform.json              子项目注册及版本标识
    feature-map.json           功能 ID → 教程 ID
    platform.R                 公共导航、页面模板和资源注册
    www/                       公共路由与项目切换
  content/biomethod/
    catalog.json               分类、文章元数据、学习路线、推荐内容
    articles/*.md              独立知识正文
    scripts.json               真实脚本映射、参数、依赖、输入输出
    references.json            可核实原始论文与官方资料
    videos.json                未来视频元数据，目前为空
    video.schema.json          视频元数据约束
```

采用单 Shiny 服务下的多模块路由，避免迁移已有分析代码。工作站 `/workstation?tool=pca` 与知识页 `/biomethod/articles/pca` 拥有独立布局与业务组件。公共模块只负责导航、主题和路由，不调用知识脚本执行分析。以后独立部署时可拆出知识 HTTP 服务及静态资源，但本版不是两个独立网站。

## 项目切换与分析任务

点击左上角 Logo 展开项目菜单，当前项目有选中状态；选择项目进入该项目首页。菜单使用原生 details/summary，可用键盘操作。浏览器 History API 支持前进、后退，文章与脚本可直接打开、刷新或在新标签打开。

同一页面内切换时，两套页面容器保持挂载，共用同一 Shiny WebSocket。切换不会终止后台 worker。选择工作站菜单会进入其首页；使用浏览器后退可回到刚才的分析视图，也可从原有任务记录查看结果。刷新或另开标签会新建浏览器会话，已有后台任务仍由工作站任务注册表管理。

路由资源基址统一为站点根目录 `/`；当前适用于启动器的本机根路径部署。如以后挂载到反向代理子路径，需要同步修改 base、资源地址和 WebSocket 路径。不要直接复制本版路由配置到子路径部署。

## 已实现功能与内容

- 四个板块：分析流程、算法原理、逐行代码教程、参考文献。
- 首页全局搜索、推荐学习路线、推荐教程与最近更新；关键词检索文章正文、脚本元数据和文献。
- Markdown 正文、R 代码高亮、`$$...$$` LaTeX 展示公式、图片、分步图示与站内链接；保留标题锚点。
- 加载、空结果、缺失页面和重试反馈；复用已有黑夜/亮色两种主题及设置。
- 19 篇文章：10 篇方法/文件介绍，9 篇独立逐行 R 技术帖，新增 GMT 基因集构建。
- 每个原理或算法配具体例子与分步图示，技术帖的每个非空代码行均有中文注释。
- 9 个真实源码索引，读取当前片段、行号和完整文件 SHA-256。
- 22 条方法论文与官方资料，保留关联与核对日期。
- GMT 教程提供可下载的成员 CSV 草表与真实 Tab 分隔格式示例。

Beta 标识统一来自 `shared/platform.json` 中 BioMethod 的 `stage`。发布时修改或删除该字段，导航与页面名称一起更新。

## 新增知识文章

1. 在 `content/biomethod/articles/` 新建唯一小写连字符 ID 的 Markdown，如 `new-method.md`。
2. 在 `catalog.json` 的 `articles` 添加对应记录；`id` 必须唯一，`file` 必须为 `id + .md`。字段参考 PCA：`title`、`title_en`、`summary`、`category`、`difficulty`、`tags`、`features`、`scripts`、`references`、`related`、`updated`、`language`、`translations`。
3. 严格使用五个二级标题并按顺序排列：定义解释、分析原理、分析操作、适用范围、参考与致谢。介绍帖设置 `article_type: concept`，只讲方法、界面操作、结果与适用条件；代码块与代码结构写成独立 `category: scripts`、`article_type: technical` 技术帖，同样使用五个主章节，按输入、处理、绘图与输出分段，每个非空代码行写中文注释。介绍帖的 `scripts` 使用空数组，以 `technical_articles` 关联技术帖 ID；真实源码索引只关联技术帖。所有文章尽量口语，每个原理或算法配例子与分步图示。图示可参考现有 `figure.bm-process`，图片放 www/figures，下载示例放 www/examples。
4. 需要推荐时，将 ID 加入 `learning_path` 或 `featured`。不需要修改前端组件；保存后刷新浏览器即可更新目录，API 每次读取磁盘内容。

正文是经过维护者审核的本地可信内容，不是面向任意用户的上传或投稿通道；Markdown 中可含 HTML，不应放入不可信来源。当前没有 CMS 或文章编辑后台。英文元数据及 translations 已预留，完整英文内容与语言切换尚未实现。

## 关联脚本、工作站功能与文献

- 在 `scripts.json` 新增稳定脚本 ID，指定 `app/` 下真实 `.R` 文件和函数名 `symbol`，并填写 `inputs`、`outputs`、`dependencies`、`parameters`、`errors`、`articles`。`max_lines` 控制展示片段，现有样板最多 95 行。`symbol: null` 表示从第一行开始展示。片段可能只覆盖函数开头，不能当作完整可执行脚本。
- 技术帖通过 `scripts` 数组关联源码索引；函数名或路径修改时同步元数据并运行内容检查。
- 功能与知识跳转由 `shared/feature-map.json` 管理；文章的 `features` 使用工作站既有工具 ID。已覆盖工具标题问号转向对应教程；没有样板覆盖的工具继续使用原帮助页。
- `references.json` 的 ID 必须唯一，填写真实论文/官方链接、作者、年份、期刊、DOI、简介、关联文章和核对日期。勿使用未经核实的引用。建议先查 DOI、PubMed 和官方软件文档。
- 增加第三个子项目：先在 `platform.json` 注册，再增加其独立容器/服务及路由适配。菜单由配置生成，但仅注册记录不会自动实现业务页面。

## 只读知识 API

| 方法与路径 | 用途 |
| --- | --- |
| GET `/api/knowledge/catalog` | 目录、脚本与文献索引；支持 `q`、`category` |
| GET `/api/knowledge/articles/:id` | 元数据、Markdown 与渲染 HTML |
| GET `/api/knowledge/scripts/:id` | 白名单脚本片段、行号、参数及 SHA-256 |
| GET `/api/knowledge/references` | 文献集合 |
| GET `/api/knowledge/references/:id` | 单条文献 |
| GET `/api/knowledge/videos` | 已发布视频元数据；当前 items 为空 |
| GET `/api/knowledge/videos/schema` | 未来视频资源 JSON Schema |

未知资源返回 404；内容配置错误返回 500 并提供重试提示。业务层写请求返回 405；本机 httpuv 的静态路径保护可能在业务层前返回 400，均不会写入数据。源文件只允许在 `scripts.json` 注册且位于工作站 `app/` 中的 R 文件；接口参数不能指定任意文件路径。`shared` 只公开 www 子目录。

## 视频预留与扩展

当前只有后端数据与接口，没有视频前端、列表、占位卡片、播放器、上传、转码或存储服务。

未来向 `videos.json` 添加符合 `video.schema.json` 的记录：ID、标题、简介、video_url、cover_url、subtitle_url、chapters（title/start_seconds）、article_ids、status。只读接口仅返回 published 记录。新增发布数据前应增加 JSON Schema、关联文章、URL 与章节顺序校验；本版空列表不引入视频处理基础设施。未来播放器需要另行开发并明确授权和资源来源。

## 开发检查

```powershell
$env:LC_ALL='English_United States.utf8'
& 'D:\R\R-4.5.1\bin\x64\Rscript.exe' --vanilla apps/biomethod/tests/content.R
node --check shared/www/platform.js
node --check apps/biomethod/www/biomethod.js
# 先启动本地 Shiny，测试仅使用内置合成 KEGG 输入
python apps/biomethod/tests/integration.py --url http://127.0.0.1:7898 --output app/tests/_integration/biomethod
python app/tests/ui-themes.py --url http://127.0.0.1:7898 --output app/tests/_browser/biomethod-regression
git diff --check
```

浏览器检查依赖开发环境已安装的 Python Playwright/Chromium，不是工作站运行依赖。测试会把默认示例设为 synthetic，原回归测试还会切换主题并恢复 night；不读取个人研究数据。测试输出放入已有 Git 忽略目录。

KaTeX 0.16.22（MIT）和 highlight.js 11.11.1（BSD-3-Clause）本地离线固定版本，原许可证与 npm 来源/完整性记录见 `www/vendor/*/LICENSE` 和 `SOURCE.json`。不是生产 CDN 依赖。

## 当前限制

第一版为人工维护、只读的 Alpha 样板，不是覆盖所有组学的完整教材。尚无 CMS、账号权限、完整英文版、增量搜索索引或视频展示。暂未测试所有浏览器和反向代理场景。原分析脚本未变更，合成 KEGG 联调不能代表全部真实人/鼠分析已重跑。

## 注释库与当前文章维护

当前有 19 篇文章（10 篇介绍与 9 篇技术帖）、9 个真实脚本入口及 22 条资料记录。文章固定五个二级标题为“定义解释、分析原理、分析操作、适用范围、参考与致谢”，右侧篇内导航已移除，标题锚点、Markdown、公式、代码与工具互跳保留。

公共注释来源统一登记在根目录 `shared/annotation-libraries.json`。知识接口 `/api/knowledge/annotations` 只读本机包版本与公共缓存；不会联网或返回研究数据与个人目录。文章元数据中的 `annotation_libraries` 可填 `["go", "kegg"]` 或 `["reactome"]`，页面自动在分析操作中附上当前信息，新文章不用复制版本号。来源日期、获取时间和数据库发行号应区分，未记录发行号时如实显示。增加脚本仍通过 `scripts.json` 登记实际 R 文件及函数，逐行技术教程独立维护，并关联当前源码供核对。

本轮记录见 [注释与知识库验收](../../app/docs/annotation-review-2026-11-08.md)。原 `tests/reading-targets.py` 入口继续可用，转至文章、颜色与互斥通路输入的浏览器验证。

## 内容维护补充（2026-11-09）

脚本解析分类先展示逐行技术教程，再提供可展开的当前源码索引。介绍帖通过 technical_articles 显示后续教程。代码每行中文注释、两类文章分离和流程图由 content.R 检查。

新增帖子时，编辑 articles 下的 Markdown，再在 catalog.json 登记标题、分类、summary、article_type 与关联。需要引文则更新 references.json 及双向关联。保存并刷新浏览器即可更新内容。代码教程配对关系、现行模板与完整验收见 [内容修订记录](../../app/docs/biomethod-editorial-2026-11-09.md)。

浏览器内容回归：`python apps/biomethod/tests/editorial-ui.py --url http://127.0.0.1:7907`。此检查只读页面与下载格式示例，使用独立本机端口。

## WGCNA图解文章（2026-11-10）

新增算法原理库条目wgcna，8张解释图与7条资料，标签涵盖共表达、转录组、模块与性状关联。文章不对应尚未实现的WGCNA工作站工具，因此features和technical_articles为空；没有虚构执行入口。图1为概念插画，图2—6和8为解释图，图7摘录原始研究MS汇总值重绘。
