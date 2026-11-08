# biometa design system

Approved direction: dark slate / warm silver / muted carmine. Surface mode: Operate. Homepage uses illustrative microscopy artwork, actual demo chart previews and existing tool navigation. Analysis surfaces prioritize readable controls and real execution status. Scientific plots remain independent of UI theme.

2026-11-09: the workstation is officially named `biometa`; existing directory names, routes and BW error codes remain compatible. Night tool cards place translucent real chart previews behind their analysis titles, like the light theme. Multiple detected runtimes require an explicit choice. Failed-task diagnostic exports stay red without animation; all other task states show a disabled gray control.

Themes: night (黑夜, default) and classic (亮色). The verdant option is retired; saved verdant settings migrate to night. Each theme uses its own generated biomedical illustration: night has membrane folds and vesicles; classic has terracotta/sage tissue and fibers on ivory. Both use normal compositing so light art remains visible. Persist via existing local settings.json, apply without reload. Theme rules live in app/www/themes.css, original styles remain intact.

Common controls use native Shiny bindings. Running state comes from worker status.json, never fabricated progress or a timer. Disable repeat submission during active execution and preserve cancellation, logs, downloads and redraw. Reference images are concepts; no mock data may masquerade as analysis output.

Bulk steps open parameter controls and wait for explicit Run. A required scientific palette at setup supplies every step's initial colors. A session-owned PNG cache supports favorites, cached layout selection and numbered full-workflow ZIP export. With step autosave enabled, a separate local checkpoint preserves inputs, parameters, completed jobs and favorites across refresh/restart; beginning a new flow replaces that checkpoint. Original job outputs remain separate.

Workflow selection uses an ordered list with grip-only drag, add/remove and a local saved preset. Step navigation distinguishes current, reached and future steps; reached steps can be revisited. Mid-step galleries contain only that step; final selection exposes all stages, favorites and size sorting. Image upload rows combine a left thumbnail, grip, top/bottom actions and the existing upload/size controls. Runtime configuration uses a single dropdown per executable. Package tables share columns and separate essential dependencies from additional installed packages.
