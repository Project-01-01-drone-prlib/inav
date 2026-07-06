# INAV 目标编译脚本用法

本仓库已经配置为 Windows PowerShell 下使用 CMake + Ninja 编译 INAV 固件目标。

已安装/使用的工具：

- CMake: `Kitware.CMake`
- Ninja: `Ninja-build.Ninja`
- Ruby: `RubyInstallerTeam.Ruby.3.4`
- ARM GCC: 由 INAV CMake 自动下载到 `tools/arm-gnu-toolchain-13.2.rel1`

## 常用命令

在仓库根目录运行：

```powershell
cd D:\88-inav-gg\inav
```

如果当前 PowerShell 禁止直接运行 `.ps1`，推荐使用仓库里的 `.cmd` 包装脚本：

```powershell
.\build-target.cmd SPEEDYBEEF405V3
```

也可以使用下面这种形式直接运行 `.ps1`：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-target.ps1 -List
```

列出可编译目标：

```powershell
.\build-target.ps1 -List
```

编译单个目标：

```powershell
.\build-target.ps1 MATEKF405
```

编译多个目标：

```powershell
.\build-target.ps1 MATEKF405 SPEEDYBEEF405V3
```

只重新生成构建环境，不编译：

```powershell
.\build-target.ps1 -ConfigureOnly
```

删除旧 CMake 缓存并重新生成：

```powershell
.\build-target.ps1 -Reconfigure -ConfigureOnly
```

清理某个目标：

```powershell
.\build-target.ps1 MATEKF405 -Clean
```

使用 Debug 或 RelWithDebInfo 构建：

```powershell
.\build-target.ps1 MATEKF405 -BuildType Debug
.\build-target.ps1 MATEKF405 -BuildType RelWithDebInfo
```

## 输出文件

默认使用 `Release` 构建，输出在：

```text
build-release
```

编译成功后，目标固件通常会生成类似：

```text
build-release\inav_9.1.0_MATEKF405.hex
build-release\inav_9.1.0_MATEKF405.bin
```

## 注意事项

- 项目文档建议 Release 模式用于生产/批量构建，磁盘占用远小于默认带调试符号的构建。
- 本机存在旧版全局 ARM 工具链，所以脚本会限制 CMake 的查找路径，确保使用仓库内的 ARM GCC 13.2.1。
- 首次配置可能较慢，因为 CMake 需要下载并解压 ARM 工具链；之后会复用 `tools/` 和 `build-release/`。
- `OpenOCD` 未安装时不会影响固件编译，只是不能直接使用本地硬件调试功能。
