# 前端维护规范

依据：[阿里巴巴前端规约](https://github.com/alibaba/f2e-spec)。本轮核对日期为 2026-11-07，上游参考提交 beb1ac899ea6dab206331263bbcdcad8f8fe336e。此文是结合工作站的适配说明，不是完整原文转载，也不表示整个项目已通过官方全套 Lint。

## 适用范围与来源

| 范围 | 参考 | 项目执行方式 |
| --- | --- | --- |
| JavaScript | [JavaScript 规约](https://github.com/alibaba/f2e-spec/blob/main/docs/coding/javascript.md) | 新增/触及代码用 2 空格、分号、单引号、const/let、清晰命名和块结构，避免未使用变量、全局污染与过长语句。 |
| CSS | [CSS 规约](https://github.com/alibaba/f2e-spec/blob/main/docs/coding/css.md) | 属性逐行、声明分号、统一空格与可读分组；复用主题变量，避免新增无必要的高优先级覆盖。 |
| HTML | [HTML 规约](https://github.com/alibaba/f2e-spec/blob/main/docs/coding/html.md) | 检查 HTML5 文档、中文语言、UTF-8、标题、viewport、显式 head/body、语义和键盘可访问性。Shiny 生成页面通过其原生参数设置。 |
| 版本与文档 | [Git 规约](https://github.com/alibaba/f2e-spec/blob/main/docs/engineering/git.md) | 提交说明写清问题与结果；记录真实验证及适用边界。 |

## 当前技术栈的适配

R Shiny 负责界面与独立 R worker 的连接，原生 JavaScript 增强交互，CSS 实现黑夜/亮色两主题；离线排版与 PPI 编辑器有独立 HTML/JS。React/TypeScript/Node 服务端条目不适用于当前实现，不因参考规约而迁移技术栈。

- Shiny 的绑定 ID、事件、依赖加载顺序和数据格式属于功能约定，不能只为调整命名或 CSS 选择器而重写。
- 保留服务器启动时必须执行的主题初始化；其他页面增强脚本可 defer，但须验证 DOMContentLoaded 与 Shiny 消息注册顺序。
- 使用 textContent 或安全的 DOM API 放入文件名、提示等外部文本；不得把用户数据当成 HTML/JavaScript 执行。
- DOM 可被 Shiny 替换。依赖任务状态的按钮必须对后续插入的控件生效，观察范围和刷新应受控；避免每次点击同步读布局。
- 提示层只管理自己的 aria-describedby 引用，不得删除其他组件的可访问描述。运行反馈尊重减少动画设置。
- 本机资源保留相对 URL；上游推荐的协议相对 CDN 地址不适合本机离线工作站，不照搬。不得为样式检查上传研究数据。
- 旧主题及 Shiny/Bootstrap 内联样式兼容层已有少数 !important 和 ID 规则，暂作兼容例外；新增规则优先用 class/主题变量，调整前验证优先级。不要批量删除导致两主题失效。
- 历史文件逐步治理。统一格式不等于修复所有语义问题，格式检查也不等于官方 ESLint/Stylelint 检查。

## 工具与检查

.editorconfig 与 .prettierrc.json 提供后续编辑默认值；.prettierignore 排除数据、缓存和第三方库。格式化工具固定使用 Prettier 3.6.2，只作为开发检查，不增加工作站运行时依赖，未配置自动 Git 钩子。

本轮整理的文件可执行：

```powershell
npx --yes prettier@3.6.2 --check app/www/workbench-ui.js app/www/themes.css
node --check app/www/workbench-ui.js
node --check app/www/toolbox.js
git diff --check
```

R 界面修改需在与启动器一致的 UTF-8 环境检查语法。行为变更还要运行浏览器检查；启动工作站后：

```powershell
python app/tests/ui-themes.py --url http://127.0.0.1:7898 --output app/tests/_browser/frontend
```

该测试使用 Python Playwright，检查两主题、21 个导航入口、示例持久化、语言与提示描述、动态按钮及合成 KEGG 的启动、取消、完成、下载、重绘；不读取个人研究数据。仅当改动与其覆盖范围有关时运行，不以重复全部分析代替定位问题。

## 变更尺度

局部兼容、可访问性、格式和明确缺陷可直接修正。架构/框架迁移、整体导航/视觉重构或执行链路变化先整理方案征求同意。用户已授权的范围继续推进；不要把规范引用变成额外的普遍审批门槛。
