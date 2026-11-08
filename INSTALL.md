# biometa (Beta) / BioMethod (Beta) 安装

版本：0.2.0-beta.1。源码发布渠道为本仓库 main，ZIP 和 Git 使用同一份源码。本机已验证 Windows + R 4.5.1，其他 R 版本需自行检查包兼容性。

## 方式一：下载 ZIP

从[官方仓库下载 ZIP](https://github.com/Aniyasama-hub/BioWorkbench/archive/refs/heads/main.zip)，或使用仓库 Code → Download ZIP，完整解压到可写目录。本地另提供的版本包可以用随包 SHA256 检查。不要直接在压缩包内启动。ZIP 包含程序和示例，不包含 R、用户数据、任务结果、注释运行缓存和个人设置。

先安装 R。在该 R 中准备依赖：

```r
install.packages("BiocManager", repos="https://cloud.r-project.org")
```

然后在解压目录执行下述命令，将 Rscript 地址换成实际选择的版本：

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' app/tools/bootstrap.R --install
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' app/tools/bootstrap.R --check
.\Start.cmd
```

首次启动浏览选择 Rscript.exe；在设置中可嗅探多个版本、指定环境和检查依赖。更换 R 后重启。联网安装需要访问 CRAN/Bioconductor，公共通路分析初次运行还需要获取相应注释；可另行使用物种和编号类型相符的本地 GMT。

## 方式二：官方仓库

安装 Git 和 R 后，从同一个[官方仓库](https://github.com/Aniyasama-hub/BioWorkbench)获取源码：

```powershell
git clone https://github.com/Aniyasama-hub/BioWorkbench.git
cd BioWorkbench
```

其后的依赖配置、检查和启动与 ZIP 相同。以后更新先保存任务与个人数据，在独立目录安装新版；不要把本机的 results/settings 当作源码上传。

## 启动与诊断

默认地址是 `http://127.0.0.1:7878`，端口冲突时看启动窗口。保留启动窗口，关闭服务会结束其任务。失败任务可在任务记录导出诊断包；其中含该任务输入，分享前确认接收范围。程序不是云服务，不会自动上传研究数据。

本轮只验证既有本机依赖环境，没有在全新 Windows 上实际联网安装所有依赖；完整安装体验仍属于发布前人工验证范围。
