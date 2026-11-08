# Product

## Platform
web

## Stack
Local R Shiny, existing R worker scripts, HTML/CSS/JavaScript. Local data and results remain local.

## Audience and jobs
Chinese-speaking biomedical researchers studying cancer, immunity and drug delivery. Current scope is human/mouse Bulk RNA-seq analysis and scientific plotting; future multiomics is a direction, not a currently supported feature.

## Confirmed constraints
Preserve real scripts, algorithms, inputs, exports and calculation/redraw separation. Tools, settings and actions must connect to real backend behavior. Examples and interface themes are selected in Settings. Default aesthetic approved from generated homepage and KEGG mockups: dark slate, silver text, restrained carmine, biomedical imagery. Keep only 黑夜 (night) and 亮色 (classic), as confirmed on 2026-11-08; retire green/copper. User officially named the workstation `biometa` on 2026-11-09; preserve its existing directory and route compatibility.

Bulk workflows may use the default plan or a user-ordered selection of existing tools. Each step waits for explicit execution; revisiting is supported and rerunning invalidates following results in the current flow. Saved workflow presets are local settings and survive image-cache cleanup. Annotation parameters allow explicit identifier/name columns with mapping audit exports. No video frontend is introduced.
