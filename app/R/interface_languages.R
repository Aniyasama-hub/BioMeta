# Self-contained exported editors need no translation service or JSON fetch.
tb_localize_editor <- function(html, root) {
  catalogs <- lapply(c("zh-TW", "en", "fr"), function(id)
    jsonlite::read_json(file.path(root, "www/locales", paste0(id, ".json"))))
  names(catalogs) <- c("zh-TW", "en", "fr")
  language <- if (exists("tb_read_settings", mode = "function")) tb_read_settings(root)$language else "zh-CN"
  encoded <- gsub("<", "\\u003c", jsonlite::toJSON(catalogs, auto_unbox = TRUE), fixed = TRUE)
  script <- paste(readLines(file.path(root, "www/i18n.js"), encoding = "UTF-8"), collapse = "\n")
  css <- paste(readLines(file.path(root, "www/i18n.css"), encoding = "UTF-8"), collapse = "\n")
  addition <- paste0("<style>", css, "</style><script>window.BiometaLanguage=",
    jsonlite::toJSON(language, auto_unbox = TRUE), ";window.BiometaLocales=", encoded,
    ";</script><script>", script, "</script>")
  sub("</body>", paste0(addition, "</body>"), html, fixed = TRUE)
}
