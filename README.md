# common_init

一些常用的初始化动作

## Linux / macOS

```bash
./setup
```

## Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

执行流程：

1. `choco`：检查 chocolatey，已安装则跳过，未安装则自动安装。
   安装需要管理员权限，脚本在非管理员环境下会自动提权重跑。
2. `windows\build.ps1`：列出可安装的应用（cmake / make），输入编号选择，
   `a` = 全部安装，直接回车 = 跳过；已安装的应用会标记出来并自动跳过。
3. `windows\gui.ps1`：列出装机必选应用（notepad++ / obsidian / ultraedit / listary），选法同第 2 步。

可选参数：

| 参数                        | 说明                                               |
| --------------------------- | -------------------------------------------------- |
| `-List`                     | 只列出步骤状态和可安装的应用，不做任何安装         |
| `-All`                      | 执行全部步骤，且每个步骤都安装全部应用（不再询问） |
| `-NoBuildEssentials`        | 跳过 build essentials 步骤                         |
| `-NoGui`                    | 跳过装机必选应用步骤                               |
| `-BuildEssentials` / `-Gui` | 显式启用对应步骤（默认就是启用）                   |
| `-Help`                     | 显示帮助                                           |

两个步骤脚本的用法一致，也可以单独运行：

- `windows\build.ps1`：不带参数时交互式选择；`-Packages cmake` 只装指定应用；
  `-All` 全部安装；`-All -Force` 全部重装；`-List` 只列出应用。
- `windows\gui.ps1`：不带参数时交互式选择；`-Packages obsidian` 只装指定应用；
  `-All` 全部安装；`-List` 只列出应用。

新增要安装的工具，在对应脚本的 `$Catalog` 里加一行即可，setup.ps1 不用改。
如果某个工具可能不是用 choco 装的（比如 Listary），可以给条目加 `Probe`：
一个或多条可执行文件路径，只要有一条存在就视为已安装并跳过。
