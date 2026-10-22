#Requires -Version 5.1
<#
  安装装机需要的应用

  用法:
    .\apps.ps1                     # 列出应用，交互式选择（直接回车 = 都不装，y = 全部）
    .\apps.ps1 -All                # 安装全部应用，不再询问
    .\apps.ps1 -Packages ripgrep   # 只安装指定应用
    .\apps.ps1 -List               # 只列出应用，不安装
    .\apps.ps1 -All -Force         # 全部重新安装（包括已安装的）
#>

[CmdletBinding()]
param(
  # 要安装的应用名，如 ripgrep,notepad++
  [string[]]$Packages = @(),
  # 安装全部应用，不再询问
  [switch]$All,
  # 只列出应用，不做任何安装
  [switch]$List,
  # 已安装的应用也重新安装
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'helpers.ps1')

# 可安装的应用清单，新增工具在这里加一行即可
# 可选的 Probe: 一个或多条可执行文件路径，有任一条存在就视为已安装
# （用于不是用 choco 装的工具，choco 里查不到它）
$Catalog = @(
  [pscustomobject]@{ Name = 'cmake';    ChocoId = 'cmake';    Description = 'CMake 跨平台构建系统' }
  [pscustomobject]@{ Name = 'make';     ChocoId = 'make';     Description = 'GNU make' }
  [pscustomobject]@{ Name = 'ripgrep';  ChocoId = 'ripgrep';  Description = 'ripgrep 代码搜索（rg）' }
  [pscustomobject]@{ Name = 'fd';       ChocoId = 'fd';       Description = 'fd 文件查找' }
  [pscustomobject]@{ Name = 'fzf';      ChocoId = 'fzf';      Description = 'fzf 模糊查找' }
  [pscustomobject]@{ Name = 'nvm';      ChocoId = 'nvm';      Description = 'nvm Node.js 版本管理' }
  [pscustomobject]@{ Name = 'nodejs';   ChocoId = 'nodejs';   Description = 'Node.js 运行时' }
  [pscustomobject]@{ Name = 'uv';       ChocoId = 'uv';       Description = 'uv Python 包管理' }
  [pscustomobject]@{ Name = 'psmux';       ChocoId = 'psmux';       Description = 'windows tmux' }
  [pscustomobject]@{ Name = 'git';       ChocoId = 'git';       Description = 'git version control tool' }
  [pscustomobject]@{ Name = 'gitui';       ChocoId = 'gitui';       Description = 'git version control tool ui' }
  [pscustomobject]@{ Name = 'unzip';    ChocoId = 'unzip';    Description = 'unzip 解压工具' }
  [pscustomobject]@{ Name = 'universal-ctags'; ChocoId = 'universal-ctags'; Description = 'ctags 代码tag索引工具' }
  [pscustomobject]@{ Name = 'notepad++'; ChocoId = 'notepadplusplus'; Description = 'Notepad++ 文本编辑器' }
  [pscustomobject]@{ Name = 'obsidian';  ChocoId = 'obsidian';        Description = 'Obsidian 笔记' }
  [pscustomobject]@{ Name = 'ultraedit'; ChocoId = 'ultraedit';       Description = 'UltraEdit 文本编辑器' }
  [pscustomobject]@{
    Name = 'listary'
    ChocoId = 'listary'
    Description = 'Listary 文件搜索工具'
    # 可能是用 Listary 自己的安装包装的，choco 里查不到，用文件探测
    Probe = @('C:\Program Files\Listary\Listary.exe', 'C:\Program Files (x86)\Listary\Listary.exe')
  }
)

# 应用已安装的说明文字，未安装则返回 $null
function Get-PackageStatus {
  param(
    [object]$Item,
    [hashtable]$Installed
  )

  if ($Installed.ContainsKey($Item.ChocoId)) {
    return "已安装 $($Installed[$Item.ChocoId])"
  }

  if ($Item.PSObject.Properties['Probe']) {
    foreach ($probe in @($Item.Probe)) {
      if ($probe -and (Test-Path -LiteralPath $probe)) {
        return '已安装（非 choco）'
      }
    }
  }

  return $null
}

# 列出清单，已安装的显示版本
function Show-PackageCatalog {
  param(
    [object[]]$Catalog,
    [hashtable]$Installed
  )

  $width = 0
  foreach ($item in $Catalog) {
    if ($item.Name.Length -gt $width) { $width = $item.Name.Length }
  }
  # 编号右对齐两格，两位数的编号不会把后面的名字挤歪；已安装的追加在行尾
  $format = '[{0,2}]: {1,-' + ($width + 2) + '} {2}'

  Write-Host '可安装的应用:'
  for ($i = 0; $i -lt $Catalog.Count; $i++) {
    $item = $Catalog[$i]
    $line = $format -f ($i + 1), $item.Name, $item.Description
    $status = Get-PackageStatus -Item $item -Installed $Installed
    if ($status) { $line += "  [$status]" }
    Write-Host $line
  }
}

# 交互式选择，返回应用名数组（空数组表示什么都不装）
function Read-PackageSelection {
  param(
    [object[]]$Catalog,
    [hashtable]$Installed
  )

  Show-PackageCatalog -Catalog $Catalog -Installed $Installed
  Write-Host '  输入编号（多个用逗号分隔）= 只装这几个，y = 全部安装，n 或直接回车 = 都不装'

  $answer = Read-Host '请选择'
  # 直接回车（含非交互场景下 Read-Host 返回 $null）= 什么都不装
  if ([string]::IsNullOrWhiteSpace($answer)) { return @() }
  $answer = $answer.Trim()
  if ($answer -match '^(y|yes|a|all)$') { return @($Catalog | ForEach-Object { $_.Name }) }
  if ($answer -match '^(n|no)$') { return @() }

  $names = New-Object System.Collections.Generic.List[string]
  foreach ($token in ($answer -split '[,;\s]+')) {
    if (-not $token) { continue }
    $index = 0
    if (-not [int]::TryParse($token, [ref]$index)) {
      Write-Warn "忽略无法识别的输入: $token"
      continue
    }
    if ($index -lt 1 -or $index -gt $Catalog.Count) {
      Write-Warn "忽略超出范围的编号: $index"
      continue
    }
    $name = $Catalog[$index - 1].Name
    if (-not $names.Contains($name)) { $names.Add($name) }
  }
  return $names.ToArray()
}

# 应用名 -> 清单条目，未知的名字直接报错，重复的只保留一个
function Resolve-PackageTargets {
  param(
    [object[]]$Catalog,
    [string[]]$Names
  )

  # 从 cmd 等外部 shell 传进来时 "ripgrep,fzf" 会是单个字符串，这里再拆一次
  $normalized = @()
  foreach ($name in $Names) {
    foreach ($part in ($name -split '[,;\s]+')) {
      if ($part) { $normalized += $part }
    }
  }

  $targets = @()
  foreach ($name in $normalized) {
    $matched = @($Catalog | Where-Object { $_.Name -eq $name -or $_.ChocoId -eq $name })
    if ($matched.Count -eq 0) {
      $available = ($Catalog | ForEach-Object { $_.Name }) -join ', '
      throw "未知的应用: $name（可用: $available）"
    }
    if (-not ($targets | Where-Object { $_.ChocoId -eq $matched[0].ChocoId })) {
      $targets += $matched[0]
    }
  }
  return $targets
}

# 选择并安装：
#   -All           安装全部，不询问
#   -Packages xxx  安装指定的应用
#   都不给         交互式选择（直接回车 = 都不装，y = 全部安装）
# 已安装的自动跳过（choco 装过的，或 Probe 探测到已存在的）；-Force 可以强制重装。
# 返回安装失败的应用名数组。
function Install-PackageCatalog {
  param(
    [object[]]$Catalog,
    [string[]]$Packages = @(),
    [switch]$All,
    [switch]$Force
  )

  $installed = Get-ChocoInstalledPackages

  if ($All) {
    $selected = @($Catalog | ForEach-Object { $_.Name })
    Write-Step '已选择全部应用'
  } elseif ($Packages.Count -gt 0) {
    $selected = $Packages
  } else {
    $selected = @(Read-PackageSelection -Catalog $Catalog -Installed $installed)
  }

  $targets = @(Resolve-PackageTargets -Catalog $Catalog -Names $selected)
  if ($targets.Count -eq 0) {
    Write-Step '没有选择任何应用，跳过'
    return @()
  }

  $chocoPath = Get-ChocoPathOrThrow
  $failed = @()
  foreach ($item in $targets) {
    $status = Get-PackageStatus -Item $item -Installed $installed
    if ($status -and -not $Force) {
      Write-Step "$($item.Name) $status，跳过"
      continue
    }

    Write-Step "安装 $($item.Name) ..."
    try {
      # 用 Out-Host 把 choco 的输出直接打到控制台，否则它会混进本函数的返回值
      & $chocoPath install $item.ChocoId -y --no-progress | Out-Host
      if ($LASTEXITCODE -ne 0) {
        Write-Warn "安装 $($item.Name) 失败（choco 退出码 $LASTEXITCODE）"
        $failed += $item.Name
      }
    } catch {
      Write-Warn "安装 $($item.Name) 失败: $($_.Exception.Message)"
      $failed += $item.Name
    }
  }

  Update-PathFromRegistry
  return $failed
}

if ($List) {
  Show-PackageCatalog -Catalog $Catalog -Installed (Get-ChocoInstalledPackages)
  exit 0
}

$failed = @(Install-PackageCatalog -Catalog $Catalog -Packages $Packages -All:$All -Force:$Force)

if ($failed.Count -gt 0) {
  Write-Warn "以下应用安装失败: $($failed -join ', ')"
  exit 1
}
Write-Step '应用处理完成'
exit 0
