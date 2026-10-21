---
name: common-init-windows-scripts
description: Use when adding, editing, or debugging the Windows setup scripts in this repo (setup.ps1, windows/apps.ps1, windows/pwsh_keys.ps1, windows/fzf-for-windows-terminal.ps1, windows/helpers.ps1). Covers the mandatory UTF-8 BOM rule for .ps1 files, how to add an installable app to the catalog, the setup.ps1 step/flag conventions, the idempotent WriteOnceToFile helper for profile lines, the Set-StrictMode null traps that keep biting, and how to validate changes without installing software or touching the user's real PowerShell profile.
---

# common_init 的 Windows 脚本

这个仓库用于初始化新机器：`setup`（bash）是 Linux 侧，`setup.ps1` + `windows/*.ps1` 是 Windows 侧；两边共用的数据/配置放 `common/`。

## 布局

- `setup.ps1`（仓库根）：入口，先装 `choco`，再列出 `$StepTable` 里的步骤让用户选（默认都不执行）。
- `common/`：两个平台共用的文件（目前只有 `README.md` 占位）。Windows 脚本用 `Join-Path $PSScriptRoot '..\common'` 引用，bash 用 `$(dirname "$(readlink -f "$0")")/common`；只放数据/配置，某一边专用的脚本留在 `windows/`。
- `windows/helpers.ps1`：通用函数（`Write-Step`、`Write-Warn`、`Test-Admin`、`Update-PathFromRegistry`、`Get-ChocoPath`、`Get-ChocoPathOrThrow`、`Get-ChocoInstalledPackages`、`WriteOnceToFile`）。只定义函数、无副作用，被其他脚本 dot-source。
- `windows/apps.ps1`：唯一的应用清单 `$Catalog` + 选择/安装流程（`Show-PackageCatalog`、`Read-PackageSelection`、`Resolve-PackageTargets`、`Install-PackageCatalog`）。
- `windows/pwsh_keys.ps1`：把 `Ctrl+U` / `Ctrl+K` 两行 `Set-PSReadLineKeyHandler` 写进 `CurrentUserAllHosts` profile，靠 `WriteOnceToFile` 保证只写一次；支持 `-List` / `-Remove` / `-ProfilePath`。
- `windows/mkcd.ps1`：用 uv 在 `D:\.mkcd` 建自包含环境（`python install --install-dir` + `venv` + `pip install mkcd`），最后 `uv run python -c 'import mkcd; mkcd.install()'` 注册命令；支持 `-List` / `-Force` / `-EnvDir` / `-Python`。
- `windows/fzf-for-windows-terminal.ps1`：安装器——装 PSFzf 模块并把快捷键选项写进 `$PROFILE`。它**不再**靠被 dot-source 生效，所以 profile 里不应该留 dot-source 它的行。

## 铁律：`.ps1` 必须存成 UTF-8 with BOM

脚本里有中文提示。没有 BOM 时 Windows PowerShell 5.1 会按 ANSI 解码，轻则乱码，重则吃掉引号导致**解析失败**（踩过两次）。

`write_file` 新建的文件没有 BOM（覆盖已存在的带 BOM 文件则会保留），所以新建后**必须**补：

```powershell
# 检查：应输出 239,187,191
[System.IO.File]::ReadAllBytes('windows/apps.ps1')[0..2] -join ','

# 补 BOM
[System.IO.File]::WriteAllText($path, [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8), (New-Object System.Text.UTF8Encoding -ArgumentList 1))
```

每次改完 `.ps1` 都要复查。注意这条只针对 `.ps1`：`SKILL.md`、`README.md` 这类 markdown **不要**加 BOM（会影响 frontmatter 解析）。

## 加一个可安装应用

只改 `windows/apps.ps1` 的 `$Catalog` 一行即可，`setup.ps1` 不用动：

```powershell
[pscustomobject]@{ Name = 'ripgrep'; ChocoId = 'ripgrep'; Description = 'ripgrep 代码搜索（rg）' }
```

- `Name` 是菜单里显示/可输入的名字，`ChocoId` 是 choco 包名，两者可以不同（如 `notepad++` / `notepadplusplus`）。
- 先确认包名存在：`choco search <id> --exact --limit-output`。choco 包名大小写不敏感，PowerShell 哈希表键也不敏感，所以 `listary` 能匹配 `Listary`。
- 如果这个工具可能不是用 choco 装的，给条目加 `Probe`（一个路径或路径数组，任一存在即视为已安装）：

```powershell
[pscustomobject]@{ Name = 'listary'; ChocoId = 'listary'; Description = 'Listary 文件搜索工具'
  Probe = @('C:\Program Files\Listary\Listary.exe') }
```

安装统一用 `choco install <id> -y --no-progress`；已装的跳过，`-Force` 强制重装。

## setup.ps1 的步骤约定

- 步骤统一登记在 `$StepTable`（`Name` / `Script` / `Description`），**不再给每个步骤配 `-X` / `-NoX` 开关**。加步骤只动这张表。
- 无参数运行时列出菜单：`[ 1]: apps.ps1  "安装应用"`，输入编号（可多个）= 只执行这几个；`y` / `yes` = 全部；`n` / `no` 或直接回车 = **都不执行**。
- `apps.ps1` 的应用选择是**默认都不装**：直接回车 / `n` / `no` = 都不装，`y` / `yes` = 全部，编号 = 只装选中的（`-match` 本来就不区分大小写，不用额外处理 `Y`/`NO`）。
- `-Steps <编号或名字>`：非交互指定步骤（如 `-Steps 2`、`-Steps pwsh_keys,fzf`），这是唯一的选择参数。
- `-List`：只打印 choco 状态、步骤菜单和各脚本的 `-List`，**不允许有任何写操作**。
- `-Help`：打印用法。
- 提权（`Start-Process -Verb RunAs`）要在交互选择**之前**做，否则提权后会再问一遍；`Get-RelaunchArguments` 负责把 `-Steps` 原样传回去。
- 步骤脚本用 `& $Path` 调用（不是 dot-source），用 `$LASTEXITCODE` 判断失败，只提示不中断；总是按 `$StepTable` 的顺序跑，而不是用户输入的顺序。
- 步骤脚本要能单独运行，并支持 `-List`；`apps.ps1` 另外支持 `-Packages <name>[,<name>]` / `-All` / `-Force`。
- `pwsh_keys.ps1` / `fzf-for-windows-terminal.ps1` 不提供任何选项询问，被选中就直接配置。
- 两个菜单（`setup.ps1` 的步骤、`apps.ps1` 的应用）用同一套输入约定：直接回车 / `n` / `no` = 什么都不做，`y` / `yes` = 全部，编号 = 只选中的（`-match` 不区分大小写，不用额外处理 `Y`/`NO`）。默认“什么都不做”意味着空输入天然安全，不需要再查 `[Console]::IsInputRedirected`。
- 步骤菜单的全选分支要返回**步骤对象**（`@($StepTable)`），不是名字数组 —— 主循环按 `$_.Name` 过滤，返回字符串会在 StrictMode 下抛 `PropertyNotFoundException`。`apps.ps1` 那边返回的是名字，因为下游 `Resolve-PackageTargets` 按名字解析。
- 输出风格：`Write-Step` → `==> ...`，`Write-Warn` → `!!! ...`；列表用 `[{0,2}]: {1,-N} {2}` 对齐。

## 往 profile 里写东西：用 `WriteOnceToFile`

`setup.ps1` 会被重复执行，所以写 profile 一律走 `WriteOnceToFile -Path <file> -Line <line>`：

- 逐行 `-ceq` 精确比较（区分大小写），已有一模一样的行就返回 `$false`，不写。
- 文件不存在时自动建目录/文件；追加用 UTF-8 **带 BOM**。
- 处理了“文件末尾没有换行”的情况，不会把新行拼到上一行尾巴上。
- 不要用模糊匹配（`-like`）或去重整块配置，只认完全相同的单行。

## `Set-StrictMode -Version Latest` 下的坑（都踩过）

- 在 `$null` 上取属性或 `.Count` 会抛异常 → 函数返回值一律用 `@()` 包一层：`$targets = @(Resolve-PackageTargets ...)`。
- **反过来，`return @($genericList)` 会直接抛 `ArgumentException（参数类型不匹配）`** —— 只发生在 `List<T>` 上，普通数组和 `ArrayList` 没事。函数里收集结果用 `List[object]` 时必须 `return $selected.ToArray()`，调用方再包 `@()`。
- 函数"返回空数组"再赋值给变量会变成 `$null` → 传给 .NET API 前要包 `@()`，例如 `[System.IO.File]::WriteAllLines($path, @($kept), ...)`。
- `[pscustomobject]` 上访问不存在的属性会抛异常 → 先判断 `$Item.PSObject.Properties['Probe']`。
- 函数里执行原生命令时，它的 stdout 会混进函数返回值 → 用 `| Out-Host`（如 `& $chocoPath install ... | Out-Host`）。
- 可能被 dot-source 进 `$PROFILE` 的代码里**不要**设置 `Set-StrictMode` / `$ErrorActionPreference`，那会改掉用户整个会话的行为。
- 交互输入要先判空再 `.Trim()`：非交互场景（stdin 不是控制台）`Read-Host` 会返回 `$null`。

## 验证改动（别动用户的真实系统）

- 语法检查（不执行）：`[scriptblock]::Create([System.IO.File]::ReadAllText($f)) | Out-Null`。
- 优先走"天然无副作用"的路径：已安装的应用会进跳过分支；`-List` 只读。
- **不要**跑 `-All`：这台机器上 `ultraedit` 没装，`-All` 会真的装软件。要跑先问用户。
- 安全地跑完整流程：`powershell -File setup.ps1 -Steps pwsh_keys`（幂等步骤）；或 `echo | powershell -File setup.ps1`（空输入 = 都不执行）。`echo y | powershell -File setup.ps1` 也能跑完三步—— apps 那一步读到 EOF 时默认不装，所以同样安全。
- 会改 `$PROFILE` 的功能必须用假 profile 验证：`-ProfilePath .tmp_x/fake.ps1`（必要时在包装脚本里覆盖 `$PROFILE`，但先用只读探针确认覆盖生效）。真实 `$PROFILE` 只在用户明确要求时写，且先备份。
- 交互路径可以喂管道输入测：`echo n | powershell -File windows/apps.ps1`（空回答 / `n` = 都不装）；也可以测 `99,abc` 这类非法输入。
  **绝对不要** `echo y` 或带 `13`（ultraedit）去测，那会真装软件；要验全选分支就把脚本复制到 `.tmp_*/`，把未安装应用的 `ChocoId` 改成一个已安装的包，再把 `helpers.ps1` 一起复制过去（它靠 `$PSScriptRoot` 找 helpers）。
- 不要在验证时跑 `mkcd` 步骤：会下载 Python/mkcd、改用户 PATH、清掉 profile 里的 PowerShell 别名，还可能弹 UAC；只看 `mkcd.ps1 -List` 就够了。
- 临时测试文件放仓库根的 `.tmp_*/` 下，测完**必须**删掉，然后 `git status` 确认干净。

## 这个环境里跑命令的怪癖

- 终端命令里的 `$` 会被吞掉 → 一行式里别用 `$var` / `$_`；需要字面 `$` 时用 `[char]36`（如 `[char]39` 是单引号）；逻辑稍复杂就写成临时 `.ps1` 文件跑。
- 别把 PowerShell 输出管道给 `tail` / `grep`（中文会乱码）→ 用终端工具的 `head_lines` / `tail_lines`。
