# common

Windows 和 Linux **两边都会用到**的公共文件放这里。

约定：

- **只放数据 / 配置**，不放入口脚本。入口仍然是仓库根的 `setup`（bash）和 `setup.ps1`
  （PowerShell）；只有一边用的脚本留在 `windows/` 下。
- 文件要能被两个平台直接读，内容不要依赖某一方的路径写法（比如别写死 `C:\` 或 `/home`）。
- 引用时从脚本自身位置往上找，不要写死绝对路径：

  - bash（仓库根的 `setup`）：`$(dirname "$(readlink -f "$0")")/common`
  - PowerShell（`windows/*.ps1`）：`Join-Path $PSScriptRoot '..\common'`

目前两边还没有共用的文件，这个目录先占位；以后加进来时，记得同步 `AGENTS.md` 的「目录结构」。
