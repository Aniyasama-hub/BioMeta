platform_config <- function(root) jsonlite::read_json(file.path(root, "shared", "platform.json"))
platform_label <- function(project) paste0(project$name_en,
  if (!is.null(project$stage) && nzchar(project$stage)) paste0(" (", project$stage, ")") else "")
platform_switcher <- function(root, current) {
  projects <- platform_config(root)$projects
  active <- Filter(function(p) identical(p$id, current), projects)[[1L]]
  tags$details(class = "platform-switcher",
    tags$summary(class = "brand", div(class = "brand-symbol", "B"),
      div(strong(platform_label(active)), tags$small(active$name))),
    tags$nav(class = "platform-projects", `aria-label` = "切换子项目",
      lapply(projects, function(p) tags$a(href = p$route, `data-project-option` = p$id,
        `aria-current` = if (p$id == current) "page", strong(platform_label(p)), tags$small(p$name)))))
}
platform_assets <- function(root) {
  tools <- tb_tool_catalog()
  boot <- list(projects = platform_config(root)$projects,
    features = jsonlite::read_json(file.path(root, "shared", "feature-map.json")), tools = as.list(c("home", "bulk", tools$id)),
    feature_labels = as.list(c(home = "工作站首页", bulk = "Bulk 自动流程", stats::setNames(tools$title, tools$id))))
  tagList(tags$link(rel = "stylesheet", href = "/platform-assets/platform.css"),
    tags$link(rel = "stylesheet", href = "/biomethod-assets/biomethod.css"),
    tags$link(rel = "stylesheet", href = "/biomethod-assets/vendor/katex/katex.min.css"),
    tags$link(rel = "stylesheet", href = "/biomethod-assets/vendor/highlight/github-dark.min.css"),
    tags$script(id = "platform-config", type = "application/json", HTML(jsonlite::toJSON(boot, auto_unbox = TRUE))),
    tags$script(src = "/biomethod-assets/vendor/katex/katex.min.js", defer = "defer"),
    tags$script(src = "/biomethod-assets/vendor/katex/auto-render.min.js", defer = "defer"),
    tags$script(src = "/biomethod-assets/vendor/highlight/highlight.min.js", defer = "defer"),
    tags$script(src = "/biomethod-assets/vendor/highlight/r.min.js", defer = "defer"),
    tags$script(src = "/biomethod-assets/biomethod.js", defer = "defer"),
    tags$script(src = "/platform-assets/platform.js", defer = "defer"))
}
biomethod_shell <- function(root, active = FALSE) {
  div(id = "biomethod-root", class = "platform-view bm-app", hidden = if (!active) "hidden",
    tags$aside(class = "bm-sidebar", platform_switcher(root, "biomethod"),
      tags$nav(`aria-label` = "BioMethod 知识导航", tags$a(href = "/biomethod", "知识首页"),
        tags$a(href = "/biomethod/category/workflows", "分析流程库"),
        tags$a(href = "/biomethod/category/methods", "算法原理库"),
        tags$a(href = "/biomethod/category/scripts", "脚本解析库"),
        tags$a(href = "/biomethod/category/references", "参考文献库")),
      p(class = "bm-sidebar-note", "理解方法，再判断结果。", tags$br(), "内容与分析脚本独立维护。")),
    tags$main(class = "bm-main", div(class = "bm-topbar", tags$a(href = "/workstation", "返回分析工作站"),
      tags$button(type = "button", `data-platform-settings` = "true", "设置")),
      div(id = "bm-content", `aria-live` = "polite", `aria-busy` = "true", p("正在读取知识内容…"))))
}

# Base precedes Shiny dependencies so nested URLs resolve their scripts before parsing.
platform_document <- function(page) {
  htmltools::htmlTemplate(text_ = paste0(
    '<!doctype html><html lang="zh-CN"><head><base href="/">',
    '{{ headContent() }}</head>{{ body }}</html>'),
    body = tags$body(page), document_ = TRUE)
}
