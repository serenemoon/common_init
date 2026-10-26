# AGENTS.md

给在本仓库里干活的 agent 看的：项目是什么、脚本怎么组织、改动要守哪些规矩。
人类向的用法见 `README.md`；Windows 脚本的详细踩坑记录见
`.agents/skills/common-init-windows-scripts/SKILL.md`。

## 项目是什么

新机器初始化脚本，Linux 和 Windows 两套，互不依赖：

| 平台 | 入口 | 做的事 |
| --- | --- | --- |
| 通用 | `Makefile` | 跟平台无关的小命令（目前是 git alias），按分组命名 |
| Linux / macOS | `./setup`（bash） | tmux 配置与源码编译、fzf、git alias、nvim 配置 |
| Windows | `.\setup.ps1`（PowerShell 5.1+） | choco、应用安装、命令行键位、fzf 快捷键 |

### Linux 侧：`setup`

单个 bash 文件，每个功能一个 `setup_for_xxx` 函数，用 `ENABLE_XXX` 变量控制是否执行，
参数形如 `--tmux-conf` / `--no-tmux-conf`，另有 `--all`、`--list`、`-h`。
写 rc 文件靠 `_addlineto`（`grep -F` 命中就不重复写）。
`external/`、`bin/` 是下载/编译产物，已在 `.gitignore` 里。
`.psmux.conf` 放在 `common/`，Windows 侧由 `psmux.ps1` 拷到用户根目录；
Linux 侧的 `setup_for_tmux_conf` 则是克隆 oh-my-tmux 到 `external/` 并软链 `.tmux.conf`。
**git alias 不在 `setup_for_git` 里**，统一在 `Makefile` 的 `git-aliases`（两个平台共用一套）；
`setup_for_git` 只留 sslverify / excludesfile / oh-my-zsh 那几项。

### Windows 侧：`setup.ps1` + `windows/`

`setup.ps1` 是入口：

1. **步骤 0（隐式）**：检查 choco，没装就装（需要管理员，非管理员会自动提权重跑）。
2. 列出 `$StepTable` 里的步骤，等用户选择（默认什么都不做），然后按表里的顺序执行。

| 步骤 | 脚本 | 作用 |
| --- | --- | --- |
| `apps` | `windows/apps.ps1` | 按 `$Catalog` 安装应用，已装的自动跳过 |
| `pwsh_keys` | `windows/pwsh_keys.ps1` | 把 `Ctrl+U` / `Ctrl+K` 写进 `CurrentUserAllHosts` profile |
| `fzf` | `windows/fzf-for-windows-terminal.ps1` | 装 PSFzf 模块，把 `Ctrl+F` / `Ctrl+R` / `Alt+C` 的配置块写进 `$PROFILE` |
| `mkcd` | `windows/mkcd.ps1` | 用 uv 在 `D:\.mkcd` 建独立环境并装 mkcd（Linux 命令集），需要 uv |
| `psmux` | `windows/psmux.ps1` | 把 `common\.psmux.conf` 拷到用户根目录（内容相同则跳过，源文件为空则拒绝） |

`windows/helpers.ps1` 只放无副作用的公共函数（`Write-Step`、`Write-Warn`、`Test-Admin`、
`Get-ChocoPath`、`Get-ChocoInstalledPackages`、`WriteOnceToFile` …），被其他脚本 dot-source。

**两个菜单共用一套输入约定**（`setup.ps1` 选步骤、`apps.ps1` 选应用）：

| 输入 | 行为 |
| --- | --- |
| 直接回车 / 空 / `n` / `no` | **什么都不做**（默认） |
| `y` / `yes`（`a` / `all` 也接受） | 全部 |
| 编号，如 `2` 或 `3,5,11` | 只做这几个 |

`setup.ps1` 的参数只有 `-Steps <编号或名字>`（非交互指定步骤）、`-List`（只读）、
`-Help`，以及 `-- <参数...>`——`--` 后面的参数原样透传给被执行的步骤脚本
（选多个步骤时每个都会收到）。

## 目录结构

```
setup                     # Linux/macOS 初始化（bash）
setup.ps1                 # Windows 初始化入口
Makefile                  # 通用命令入口，make help 按分组列出
common/                   # 两个平台共用的文件（.psmux.conf 等）
windows/apps.ps1          # 应用清单 $Catalog + 选择/安装流程
windows/pwsh_keys.ps1     # 命令行键位（写 CurrentUserAllHosts profile）
windows/fzf-for-windows-terminal.ps1  # PSFzf 快捷键（写 $PROFILE 配置块）
windows/mkcd.ps1          # 用 uv 装 mkcd（Linux 命令集）
windows/psmux.ps1         # 把 common/.psmux.conf 拷到用户目录
windows/helpers.ps1       # 公共函数
.agents/skills/…          # 本仓库的 agent skill（Windows 脚本细则）
```

## 改动规则

1. **`.ps1` 必须存成 UTF-8 with BOM。** 脚本里有中文，没有 BOM 时 PowerShell 5.1 按 ANSI
   解码，轻则乱码，重则吃掉引号导致解析失败。新建后用
   `[System.IO.File]::ReadAllBytes($f)[0..2]` 确认是 `239,187,191`，不对就补：

   ```powershell
   [System.IO.File]::WriteAllText($p,
     [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8),
     (New-Object System.Text.UTF8Encoding -ArgumentList 1))
   ```

   `AGENTS.md`、`README.md`、`SKILL.md` 这类 markdown **不要**加 BOM（会破坏 frontmatter/首行）。

2. **单一事实来源，别加新开关。** 加应用只改 `windows/apps.ps1` 的 `$Catalog` 一行
   （`Name` / `ChocoId` / `Description`，可选 `Probe`）；加步骤只改 `setup.ps1` 的
   `$StepTable` 一行。**不要**再给步骤加 `-X` / `-NoX` 之类的参数，`-Steps` 已经够用。
   两个平台都要用的文件放 `common/`，别在 `windows/` 和 Linux 脚本里各抄一份；
   引用时用 `$PSScriptRoot` / `dirname $0` 相对定位，不写死绝对路径。

3. **幂等。** `setup.ps1` 会被反复执行：装东西前先探测（choco 列表 / `Probe`），
   写 profile 一律走 `WriteOnceToFile -Path -Line`（逐行 `-ceq` 精确比较，已有就不写）。

4. **兼容 Windows PowerShell 5.1。** 文件头保留 `#Requires -Version 5.1`，别用 PS 7 专有
   语法（`??`、`-LeafBase`、三元运算等）。`Get-PSReadLineKeyHandler` 在 2.0.0 上**没有**
   `-Chord` 参数。

5. **`Set-StrictMode -Version Latest` 的坑**（详见 skill）：
   - `$null.Count` / `$null` 上取属性会抛异常 → 返回值用 `@()` 包一层；
   - `return @($genericList)` 会抛 `ArgumentException（参数类型不匹配）` →
     用 `return $list.ToArray()`；
   - `[pscustomobject]` 上访问不存在的属性会抛异常 → 先查 `$Item.PSObject.Properties['x']`；
   - 函数里的原生命令 stdout 会混进返回值 → 用 `| Out-Host`；
   - 会被 dot-source 进 profile 的代码里**不要**设置 `Set-StrictMode` / `$ErrorActionPreference`；
   - `Read-Host` 在非交互 stdin 下可能返回 `$null` → 先 `IsNullOrWhiteSpace` 再 `.Trim()`。

6. **提权要放在交互之前。** 否则提权后的新进程会再问一遍；`Get-RelaunchArguments` 负责把
   `-Steps` 原样传给新进程。

7. **输出风格统一**：`Write-Step` → `==> ...`（青色），`Write-Warn` → `!!! ...`（黄色）；
   列表用 `[{0,2}]: {1,-N} {2}` 对齐，方便肉眼扫。

8. **改完同步文档**：功能/参数变了要改 `README.md`；踩到新的坑或约定变了，改
   `.agents/skills/common-init-windows-scripts/SKILL.md`。

9. **临时文件**：需要临时脚本就放仓库根的 `.tmp_*/` 下，用完**必须删掉**，最后用
   `git status` 确认干净。别把临时文件提交进去。

10. **提交信息**：按用户的全局规则——主题用祈使句、首字母大写、≤50 字符、结尾不加标点；
    正文按 72 列折行，别重复主题；**正文里避免 `$` 字符**（终端会吞掉，改写成
    "the PowerShell profile" 之类）。

11. **Makefile 命令**：目标名用「分组-动作」（如 `git-aliases`），同时更新 `help` 里对应
    分组并加进 `.PHONY`，命令要幂等。文案用英文（原生 make 在 Windows 控制台输出中文
    会乱码），注释用中文。

## 验证（不要动真机）

这台开发机上 `ultraedit` **没装**，所以下面这些命令是安全的：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -List          # 只读
powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Steps 2       # 只跑幂等步骤
powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Help
echo | powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1          # 空输入 = 都不做
echo n | powershell -NoProfile -ExecutionPolicy Bypass -File windows/apps.ps1 # 都不装
echo 1,3 | powershell -NoProfile -ExecutionPolicy Bypass -File windows/apps.ps1 # 已装的只会跳过
```

**不要**做的事：

- 不要跑 `-All`、不要 `echo y` 喂给 `apps.ps1`、不要输入 `13`——都会真的装软件。
  要验"全选"分支，把脚本复制到 `.tmp_*/`，把未安装应用的 `ChocoId` 改成一个已安装的包，
  并把 `helpers.ps1` 一起复制过去（它靠 `$PSScriptRoot` 找）。
- 不要随手改用户真实的 `$PROFILE`。先用 `-ProfilePath .tmp_*/fake.ps1` 测；确需改真文件，
  先备份成 `*.bak-<时间戳>`。
- 不要在验证时跑 `mkcd` 步骤：它会下载 Python 和 mkcd 包，改用户 PATH、清掉 profile 里的
  PowerShell 别名，还可能弹 UAC。验它只跑 `windows\mkcd.ps1 -List`（只读）。
- 不要把 PowerShell 输出管道给 `tail` / `grep`（中文会乱码），需要截取就用工具自带的
  行数限制。
- 终端里的一行式命令避免 `$var` / `$_`（shell 会吞掉 `$`），复杂逻辑写成临时 `.ps1` 跑。
