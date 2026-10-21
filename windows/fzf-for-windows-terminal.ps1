#Requires -Version 5.1
<#
  fzf-for-windows-terminal

  用 PSFzf 模块（https://github.com/kelleyma49/PSFzf）给 Windows Terminal 里的
  PowerShell 加 fzf 快捷键:

    Ctrl+F  模糊查找当前目录下的文件，回车把路径贴到命令行
    Ctrl+R  模糊过滤历史命令行，回车把选中的命令填到命令行
    Alt+C   模糊查找当前目录下的子目录，回车进入该目录

  做法很简单: 装好 PSFzf 模块，再把下面这几行写进 $PROFILE（幂等）：

    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+f' -PSReadlineChordReverseHistory 'Ctrl+r' `
                    -PSReadlineChordSetLocation 'Alt+c' [-EnableFd]

  用法:
    .\fzf-for-windows-terminal.ps1            # 装模块 + 写 profile 配置
    .\fzf-for-windows-terminal.ps1 -List      # 只看状态，不做改动
    .\fzf-for-windows-terminal.ps1 -Remove    # 从 profile 里移除配置
    .\fzf-for-windows-terminal.ps1 -Force     # 强制重装/升级 PSFzf 模块

  依赖:
    fzf        快捷键本身要用（windows\apps.ps1 的清单里有）
    fd         可选；装了就在 profile 里加上 -EnableFd，列文件更快（清单里也有）
#>

[CmdletBinding()]
param(
  # 要操作的 profile 文件，默认 $PROFILE
  [string]$ProfilePath = $PROFILE,
  # 从 profile 里移除配置块
  [switch]$Remove,
  # 只显示状态，不做改动
  [switch]$List,
  # 强制重装/升级 PSFzf 模块
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'helpers.ps1')

if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
  throw '拿不到 profile 路径，请用 -ProfilePath 显式指定'
}

$ModuleName = 'PSFzf'
$BeginMarker = '# >>> fzf-for-windows-terminal >>>'
$EndMarker = '# <<< fzf-for-windows-terminal <<<'

function Get-InstalledPsFzf {
  return Get-Module -ListAvailable $ModuleName |
    Sort-Object Version -Descending | Select-Object -First 1
}

function Install-PsFzfModule {
  param([switch]$Reinstall)

  if (-not $Reinstall) {
    $existing = Get-InstalledPsFzf
    if ($existing) { return $existing }
  }

  Write-Step "安装 $ModuleName 模块（Scope CurrentUser）"
  # PowerShell 5.1 默认没开 TLS 1.2，不设连不上 PSGallery
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Install-Module -Name $ModuleName -Scope CurrentUser -Force
  Write-Step "$ModuleName 安装完成"

  $installed = Get-InstalledPsFzf
  if (-not $installed) { throw "$ModuleName 安装后仍未找到，请手动检查" }
  return $installed
}

# 生成要写进 profile 的配置块（fd 可用时顺带打开 -EnableFd）
function New-ProfileBlock {
  param([switch]$UseFd)

  $options = "-PSReadlineChordProvider 'Ctrl+f' -PSReadlineChordReverseHistory 'Ctrl+r' " +
    "-PSReadlineChordSetLocation 'Alt+c'"
  if ($UseFd) { $options += ' -EnableFd' }

  return @(
    $BeginMarker
    "Import-Module $ModuleName -ErrorAction SilentlyContinue"
    "Set-PsFzfOption $options"
    $EndMarker
  )
}

# 取出 profile 里现有的配置块（没有则返回空数组）
function Get-ProfileBlockLines {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) { return @() }

  $lines = @(Get-Content -LiteralPath $Path)
  $begin = [array]::IndexOf($lines, $BeginMarker)
  if ($begin -lt 0) { return @() }

  $end = [array]::IndexOf($lines, $EndMarker, $begin)
  if ($end -lt 0) { $end = $lines.Count - 1 }
  return @($lines[$begin..$end])
}

# 去掉 profile 里的配置块，以及旧版本那行 dot-source 本脚本的引用
# （旧版本靠被 dot-source 生效，现在改成写配置块了，留着它每开一个 shell 都会跑一遍安装逻辑）
function Remove-ProfileBlock {
  param([string]$Path)

  $selfName = Split-Path -Leaf $PSCommandPath
  $kept = New-Object System.Collections.Generic.List[string]
  $inBlock = $false
  foreach ($line in (Get-Content -LiteralPath $Path)) {
    if ($line -eq $BeginMarker) { $inBlock = $true; continue }
    if ($line -eq $EndMarker) { $inBlock = $false; continue }
    if ($inBlock) { continue }
    if ($line.IndexOf($selfName, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
    $kept.Add($line)
  }
  return $kept.ToArray()
}

$psFzf = Get-InstalledPsFzf
$block = @(Get-ProfileBlockLines -Path $ProfilePath)
$hasFd = [bool](Get-Command fd -ErrorAction SilentlyContinue)

# ---------------------------------------------------------------- 只看状态
if ($List) {
  if ($psFzf) {
    Write-Step "$ModuleName : 已安装 $($psFzf.Version)  ->  $($psFzf.Path)"
  } else {
    Write-Step "$ModuleName : 未安装"
  }
  Write-Step "profile   : $ProfilePath"
  if ($block.Count -eq 0) {
    Write-Host '  配置: 未写入'
  } else {
    Write-Host '  配置: 已写入'
    foreach ($line in $block) { Write-Host "  $line" }
  }
  if ($hasFd) {
    Write-Host '  fd: 有（会启用 -EnableFd）'
  } else {
    Write-Host '  fd: 没有'
  }
  exit 0
}

# ---------------------------------------------------------------- 移除配置
if ($Remove) {
  if (-not (Test-Path -LiteralPath $ProfilePath)) {
    Write-Step 'profile 不存在，无需移除'
    exit 0
  }
  $original = @(Get-Content -LiteralPath $ProfilePath)
  $cleaned = @(Remove-ProfileBlock -Path $ProfilePath)
  if ($cleaned.Count -eq $original.Count) {
    Write-Step 'profile 里没有本脚本的配置，无需移除'
    exit 0
  }
  [System.IO.File]::WriteAllLines($ProfilePath, $cleaned, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
  Write-Step "已从 $ProfilePath 移除配置"
  exit 0
}

# ---------------------------------------------------------------- 安装/更新
$psFzf = Install-PsFzfModule -Reinstall:$Force

if ($block.Count -gt 0) {
  Write-Step 'profile 里已经配置过了，跳过（内容见下）'
  foreach ($line in $block) { Write-Host "  $line" }
} else {
  $newBlock = @(New-ProfileBlock -UseFd:$hasFd)

  # 先清掉旧版本留在 profile 里的 dot-source 行，再追加配置块
  if (Test-Path -LiteralPath $ProfilePath) {
    $original = @(Get-Content -LiteralPath $ProfilePath)
    $cleaned = @(Remove-ProfileBlock -Path $ProfilePath)
    if ($cleaned.Count -ne $original.Count) {
      [System.IO.File]::WriteAllLines($ProfilePath, $cleaned, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
      Write-Step '已清理 profile 里旧版本留下的引用'
    }
  }

  $profileDir = Split-Path -Parent $ProfilePath
  if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
  }
  if (-not (Test-Path -LiteralPath $ProfilePath)) {
    New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
  }

  # 上一行可能没有以换行结尾，先补一个
  $blockText = ($newBlock -join [Environment]::NewLine) + [Environment]::NewLine
  if ((Get-Item -LiteralPath $ProfilePath).Length -gt 0) {
    $text = [System.IO.File]::ReadAllText($ProfilePath)
    if (-not $text.EndsWith("`n")) { $blockText = [Environment]::NewLine + $blockText }
    $blockText = [Environment]::NewLine + $blockText
  }
  [System.IO.File]::AppendAllText($ProfilePath, $blockText, (New-Object System.Text.UTF8Encoding -ArgumentList $true))

  Write-Step "已写入 $ProfilePath"
  foreach ($line in $newBlock) { Write-Host "  $line" }
  Write-Host '  新开一个 shell 生效，当前窗口可以先执行: . $PROFILE'
}

if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
  Write-Warn '当前找不到 fzf，快捷键要等 fzf 装好才生效（windows\apps.ps1 的清单里有 fzf）'
}

exit 0
