# Third-party notices

## Cytoscape.js 3.30.4 — MIT

The interactive PPI viewer includes the unmodified, pinned browser distribution:

- Upstream: https://github.com/cytoscape/cytoscape.js/tree/v3.30.4
- Distribution: https://unpkg.com/cytoscape@3.30.4/dist/cytoscape.min.js
- Local file: `www/vendor/cytoscape.min.js`
- SHA-256: `1BB5340E549511E111B31E5684872C949AD33D40EA5DBA0AD8E7D90C62C7B3B9`
- License: `www/vendor/CYTOSCAPE-LICENSE.txt` (MIT, Copyright 2016–2024 Cytoscape Consortium).

The offline network export copies the library and its full license beside `network.html`. No CDN connection is needed to view an exported graph. The viewer template and application styling are local application code.

## Design and workflow references

- Linear UI redesign: https://linear.app/now/how-we-redesigned-the-linear-ui
  — reference for hierarchy and density; no Linear source code or assets copied.
- ideal RNA-seq application: https://github.com/federicomarini/ideal
  — reference for analysis workflow; upstream DESCRIPTION declares MIT + LICENSE. No ideal source code bundled.
- Cytoscape.js documentation: https://js.cytoscape.org/
  — browser graph integration.
- STRING download documentation: https://string-db.org/cgi/download
  — file confidence scores multiplied by 1000.

R dependencies remain installed packages, not copied source trees. Their original package licenses apply. Existing adapted heatmap scripts are user-project copies in `legacy/`; they are not attributed to the above MIT projects.

## Scientific palette references

The three-stop Sunset and BuRd presets use endpoints and a central colour from Paul Tol's documented colour schemes. The continuous ramp is reconstructed from those three stops. The YlOrBr preset follows the ColorBrewer sequential scheme.

- https://sronpersonalpages.nl/~pault/
- https://colorbrewer2.org/

## BioMethod offline reading libraries

- KaTeX 0.16.22 — MIT, Copyright 2013–2020 Khan Academy and other contributors. Project: https://github.com/KaTeX/KaTeX. Local distribution and full license: `../apps/biomethod/www/vendor/katex/`.
- highlight.js 11.11.1 — BSD 3-Clause, Copyright 2006 Ivan Sagalaev. Project: https://github.com/highlightjs/highlight.js. Local core, R language, theme and full license: `../apps/biomethod/www/vendor/highlight/`.

Each directory includes SOURCE.json recording the pinned npm distribution and its verified package integrity. These assets are served locally; no browser CDN requests are needed. Scientific references are maintained separately in `../content/biomethod/references.json`.

## Bundled R installation resources

R 4.6.2 for Windows — R Core Team and contributors, GPL-2 or GPL-3. Original binary installer and corresponding source are split into ordered files in ../installers/. Original COPYING and COPYRIGHTS.win, source URLs and complete archive checksums are retained there. The launcher reconstructs the installer without changing its contents. R packages are installed separately under their own licenses.
