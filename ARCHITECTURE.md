# Beta 版本结构

统一版本号和子项目标识在 `shared/platform.json`：biometa (Beta)、BioMethod (Beta)，版本 0.2.0-beta.2。

```text
Start.cmd → launcher/start.vbs → launcher/tray.ps1 → app/start.R → app/app.R
launcher/                托盘、R 探测、首次配置、图标与快捷方式生成
installers/              R 安装分卷、源码、来源和许可证
app/R/                   工作站分析、绘图、输入、设置、流程与任务诊断
app/toolbox_worker.R     独立 R 任务执行；界面不伪造计算状态
app/config/              分析配置
app/examples/            内置合成示例、九套 GEO 示例及来源/默认 DEG
app/www/                 工作站界面、双主题、四语字典、PPI 与排版编辑器
apps/biomethod/          独立知识布局、只读接口、文章/脚本渲染
content/biomethod/       Markdown、目录元数据、脚本关联与文献
shared/                  项目切换、路由、功能映射、注释来源元数据
legacy/                  保留兼容的热图分析脚本
app/tools/               依赖配置、检查、本机浏览与环境嗅探
app/docs/                使用所需的功能说明
```

两个项目共享本机 Shiny 服务，以 `/workstation`、`/biomethod` 独立路由切换；保留同一连接，正在执行的任务不因项目切换而停止。没有为发布迁移框架或大规模搬动脚本。

工作站分析与重绘分开。任务保存在 `app/results/toolbox/jobs`，含输入快照、参数、计算结果、绘图及日志；流程图片缓存与持久化流程进度分开。设置、运行缓存、日志和研究输入均不随发布包分发。公共注释导出版本、映射质量、GMT 与哈希；稳定编号优先，明确冲突默认阻断。

BioMethod 使用文章/技术帖与真实源码 ID 关联，不复制另一套分析实现。当前 18 篇文章（9 篇介绍、9 篇代码教学）、9 个源码索引、15 条文献；以当前 JSON 内容索引为准。视频只保留后端元数据，不提供前端视频页。

控制台排错入口 `launch.ps1` 仍可单独使用。公开目录只包含运行与使用所需文件；本地 Git、协作规则、测试、审查报告、缓存和结果不随程序分发。
