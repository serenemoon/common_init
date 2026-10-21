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
2. 列出可执行的步骤，**默认一个都不执行**：输入编号（多个用逗号分隔）= 只执行这几个，
   `y` / `yes` = 全部执行，`n` / `no` 或直接回车 = 都不执行：

   ```
   [ 1]: apps.ps1                      "安装应用"
   [ 2]: pwsh_keys.ps1                 "配置命令行键位（Ctrl+U / Ctrl+K）"
   [ 3]: fzf-for-windows-terminal.ps1  "配置 fzf 快捷键（Ctrl+F / Ctrl+R / Alt+C）"
   [ 4]: mkcd.ps1                      "用 uv 装一套 Linux 命令（需要 uv）"
   ```

   选中的步骤按上面的顺序执行，没选中的跳过；也可以用 `-Steps` 在命令行直接指定。

`windows\apps.ps1`（步骤 1）会列出所有可安装的应用，**默认一个都不装**：
直接回车或输入 `n` / `no` = 都不装，`y` / `yes` = 全部安装，
输入编号（如 `3,5,11`）= 只装这几个。已安装的会标记出来并自动跳过：

```
[ 1]: cmake             CMake 跨平台构建系统  [已安装 4.3.1]
[ 2]: make              GNU make  [已安装 4.4.1]
...
[13]: ultraedit         UltraEdit 文本编辑器
[14]: listary           Listary 文件搜索工具  [已安装（非 choco）]
```

应用清单不再分类，全部在 `windows\apps.ps1` 的 `$Catalog` 里：cmake、make、ripgrep、
fd、fzf、nvm、nodejs、uv、unzip、universal-ctags、notepad++、obsidian、ultraedit、listary。

可选参数：

| 参数                  | 说明                                                                 |
| --------------------- | -------------------------------------------------------------------- |
| `-Steps <编号或名字>` | 只执行指定步骤，多个用逗号分隔，如 `-Steps 2`、`-Steps pwsh_keys,fzf` |
| `-List`               | 只列出步骤状态、应用清单和各脚本的配置状态，不做任何改动             |
| `-Help`               | 显示帮助                                                             |

`windows\apps.ps1` 也可以单独运行：不带参数时交互式选择（默认都不装，`y` = 全部安装）；
`-Packages ripgrep,fzf` 只装指定应用；`-All` 全部安装；`-All -Force` 全部重装；
`-List` 只列出应用。

非交互环境（stdin 被重定向，比如在 CI 里跑）下，两个菜单的空输入都是“什么都不做”，
不会误装或误跑；要全选请显式输入 `y`，或用 `-Steps` / `-All` / `-Packages`。

### 命令行键位

`windows\pwsh_keys.ps1` 会把下面两行写进**所有 host 共用**的 profile
（`$PROFILE.CurrentUserAllHosts`，即 `Documents\WindowsPowerShell\profile.ps1`），
所以 Windows Terminal、控制台、VS Code 里的 PowerShell 都会生效：

| 快捷键   | 作用                                       |
| -------- | ------------------------------------------ |
| `Ctrl+U` | 删除光标前（行首到光标）的所有内容         |
| `Ctrl+K` | 删除光标后（光标到行尾）的所有内容         |

写入是幂等的：借助 `windows\helpers.ps1` 里的 `WriteOnceToFile`，写之前先检查文件里
是否已经有一模一样的一行（区分大小写），所以 `setup.ps1` 反复执行也只会写一次。

```powershell
.\setup.ps1 -Steps pwsh_keys                                     # 只配置键位
powershell -File .\windows\pwsh_keys.ps1 -List                   # 看状态
powershell -File .\windows\pwsh_keys.ps1 -Remove                 # 从 profile 里移除
powershell -File .\windows\pwsh_keys.ps1 -ProfilePath .\a.ps1    # 写到指定文件
```

如果 profile 里原本有 `Ctrl+u` / `Ctrl+k` 的绑定，本脚本写的行在后面，会覆盖它。
写完新开一个窗口，或先执行 `. $PROFILE` 生效。

### fzf 快捷键（可选）

基于 [PSFzf](https://github.com/kelleyma49/PSFzf) 模块，给 Windows Terminal 里的
PowerShell 加三个快捷键：

| 快捷键   | 作用                                             |
| -------- | ------------------------------------------------ |
| `Ctrl+F` | 模糊查找当前目录下的文件，回车把路径贴到命令行   |
| `Ctrl+R` | 模糊过滤历史命令行，回车把选中的命令填到命令行   |
| `Alt+C`  | 模糊查找当前目录下的子目录，回车进入该目录       |

`windows\fzf-for-windows-terminal.ps1` 会把 PSFzf 模块装好（`Install-Module -Scope
CurrentUser`），再把下面这几行写进 `$PROFILE`（幂等，已配置就跳过）：

```powershell
# >>> fzf-for-windows-terminal >>>
Import-Module PSFzf -ErrorAction SilentlyContinue
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+f' -PSReadlineChordReverseHistory 'Ctrl+r' -PSReadlineChordSetLocation 'Alt+c' -EnableFd
# <<< fzf-for-windows-terminal <<<
```

启用、看状态、取消启用：

```powershell
.\setup.ps1 -Steps fzf                                          # 只配置 fzf 快捷键
powershell -File .\windows\fzf-for-windows-terminal.ps1 -List    # 看模块和配置状态
powershell -File .\windows\fzf-for-windows-terminal.ps1 -Remove  # 从 profile 里移除
```

依赖 `fzf`（在 `apps.ps1` 的清单里）；`fd` 可选，装了就会自动加上 `-EnableFd`
（用 fd 列文件，更快）。配置完新开一个窗口，或先执行 `. $PROFILE` 生效。

两点注意：这几个 chord 会覆盖 PSReadLine 自己的绑定（比如 `Ctrl+F` 原本是光标右移）；
PSFzf 的 `Alt+C` 选完目录后会 `AcceptLine`（相当于回车执行当前命令行），所以按它时
命令行里最好别留半截命令。

### mkcd（Linux 命令集，可选）

`windows\mkcd.ps1` 用 [uv](https://docs.astral.sh/uv/) 在 `D:\.mkcd` 里建一套独立的
Python 环境，装上 PyPI 上的 [mkcd](https://pypi.org/project/mkcd/)——它把 `ls` / `cat` /
`grep` / `tail` / `tar` 等 Linux 命令带到 Windows 上：

1. `uv python install 3.14 --install-dir D:\.mkcd\python`（Python 也装在这个目录里）
2. `uv venv D:\.mkcd\.venv`
3. `uv pip install mkcd`
4. `uv run python -c "import mkcd; mkcd.install()"`

前提是有 `uv`（在应用清单里，装应用时勾上 `uv`；没有会直接报错退出）。
已经装过的步骤会自动跳过，重复执行不会重复下载。

```powershell
.\setup.ps1 -Steps mkcd                                    # 单装 mkcd
powershell -File .\windows\mkcd.ps1 -List                   # 看状态（只读）
powershell -File .\windows\mkcd.ps1                        # 装
powershell -File .\windows\mkcd.ps1 -Force                  # 全部重来
powershell -File .\windows\mkcd.ps1 -EnvDir E:\.mkcd -Python 3.13
```

`mkcd.install()` 会把命令目录加进 PATH（会问要不要用管理员权限改系统 PATH，
拒绝就只改用户 PATH），并清掉冲突的 PowerShell 别名（`ls` / `cat` / `rm` / `pwd` /
`tee` 等）。所以装完要**新开一个终端**。想撒销：先跑 `D:\.mkcd\.venv\Scripts\mkcd-uninstall.exe`，
再删掉整个 `D:\.mkcd` 目录即可。

新增要安装的工具，在 `windows\apps.ps1` 的 `$Catalog` 里加一行即可，setup.ps1 不用改。
如果某个工具可能不是用 choco 装的（比如 Listary），可以给条目加 `Probe`：
一个或多条可执行文件路径，只要有一条存在就视为已安装并跳过。

新增一个步骤，则在 `setup.ps1` 的 `$StepTable` 里加一行（脚本名 + 描述），菜单和 `-Steps`
会自动识别它，不用再为它加开关参数。
