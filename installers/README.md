# R 安装资源

内置 Windows 安装包：R 4.6.2。原文件按 8 MiB 拆成 `R-4.6.2-win.exe.part001` 至 `part011`。启动器按顺序合并并核对 SHA256，无须手工操作。

- 国内镜像：https://mirrors.tuna.tsinghua.edu.cn/CRAN/bin/windows/base/R-4.6.2-win.exe
- 官方文件：https://cran.r-project.org/bin/windows/base/R-4.6.2-win.exe
- 官方 MD5：https://cran.r-project.org/bin/windows/base/md5sum.R-4.6.2.txt
- 对应源码：https://cran.r-project.org/src/base/R-4/R-4.6.2.tar.gz
- 完整安装包大小：91,363,600 字节
- MD5：`d01b7413cce5540a35eaf8295ef32197`
- SHA256：`b0b0053baa1963b6d8a28c9642d50107ef9ce2f41c8b9a90e952846c8918b38a`

R 由 R Core Team 及贡献者维护，按 GPL-2 或 GPL-3 分发。安装包版权和许可保持原样，对应源代码和许可证一并提供。R 安装包不包含工作站全部软件包；依赖仍需通过 CRAN/Bioconductor 准备。

对应源码分卷为 R-4.6.2.tar.gz.part001 至 part005，按文件名顺序二进制拼接即可还原；完整 SHA256 见 r-source.json。COPYING 和 COPYRIGHTS.win 保留原版权与许可说明。源码分卷供获取对应源码使用，不参与工作站启动。
