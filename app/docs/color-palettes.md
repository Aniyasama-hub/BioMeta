# 科研配色怎么选

先考虑颜色表达什么，再选择方案。点开预设即可应用；色尺从左到右表示低值到高值。可用取色器、HEX 或 RGB 修改，填写名称后保存至“我的配色”，重启工作站后仍可调用。同名保存会更新原预设。

- **连续数值**：Viridis、Cividis 从暗到亮，适合表达量、评分或富集强度。内置五个采样色；不用于暗示互不相关的多个类别。
- **正负变化**：RdBu、PuOr、BrBG 用浅色表示中间值，两侧表示不同方向。适合按行标准化热图；结合色尺确认零值位置。
- **两组对比**：Okabe–Ito 蓝橙选取原方案中的蓝和朱红，可区分实验组与对照组。中间灰用于未达到阈值的点；这不是完整八色分类方案。
- **个性风格**：Quietude 等方案用于风格探索，正式出图前检查相邻颜色、标签和黑白打印是否清楚。任何配色都应配合图例解读。

## 来源与维护

色值以公开方案及作者资料为依据；现有个性风格方案继续保留。连续色尺采用离散采样后插值，属于原色图的近似。

- [Matplotlib：选择色图](https://matplotlib.org/stable/users/explain/colors/colormaps.html)
- [Matplotlib：原始色值](https://github.com/matplotlib/matplotlib/blob/main/lib/matplotlib/_cm_listed.py)
- [Okabe 与 Ito：色觉友好设计](https://jfly.uni-koeln.de/color/)
- [ColorBrewer](https://colorbrewer2.org/)
- [Paul Tol 配色说明](https://sronpersonalpages.nl/~pault/)

维护预设：修改 `app/R/style_schema.R` 的 `tb_palettes()`；更新本文件即可同步界面说明。个人预设保存在本机 `app/results/toolbox/palette_presets.json`，不随代码发布。
