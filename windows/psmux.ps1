#Requires -Version 5.1
<#
  psmux — 把 common\ 下的 .tmux.* 配置拷到用户根目录

  仓库里的 tmux 配置统一放在 common\ 下：Linux 侧由 ./setup 软链到
  ~/.config/tmux/，Windows 侧直接拷到用户根目录：

    common\.tmux.conf        ->  %USERPROFILE%\.tmux.conf
    common\.tmux.conf.local  ->  %USERPROFILE%\.tmux.conf.local

  common\ 下以后再加 .tmux.* 的文件也会一起拷过去。
  内容相同的文件会跳过，所以重复执行没有副作用。

  用法:
    .\psmux.ps1                      # 拷贝（已一致的文件跳过）
    .\psmux.ps1 -List                # 只看状态，不做改动
    .\psmux.ps1 -Destination D:\x    # 拷到指定目录（默认用户根目录）
#>

[CmdletBinding()]
param(
  # 拷到哪里，默认用户根目录（$HOME）
  [string]$Destination = $HOME,
  # 只看状态，不做改动
  [switch]$List
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'helpers.ps1')

$CommonDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'common'
if ([string]::IsNullOrWhiteSpace($Destination)) { $Destination = $HOME }

# common\ 下所有 .tmux.* 文件（没有则返回空数组）
function Get-TmuxFiles {
  param([string]$Dir)

  if (-not (Test-Path -LiteralPath $Dir)) { return @() }
  return @(Get-ChildItem -LiteralPath $Dir -File |
    Where-Object { $_.Name -like '.tmux.*' } |
    Sort-Object Name)
}

# 两个文件内容是否一致；目标不存在时返回 $false
function Test-SameContent {
  param(
    [string]$Source,
    [string]$Target
  )

  if (-not (Test-Path -LiteralPath $Target)) { return $false }
  $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
  $targetHash = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash
  return $sourceHash -eq $targetHash
}

$files = @(Get-TmuxFiles -Dir $CommonDir)
if ($files.Count -eq 0) {
  Write-Warn "没有找到 $CommonDir 下的 .tmux.* 文件"
  exit 1
}

# ---------------------------------------------------------------- 只看状态
if ($List) {
  Write-Step "源目录  : $CommonDir"
  Write-Step "目标目录: $Destination"
  foreach ($file in $files) {
    $target = Join-Path $Destination $file.Name
    if (Test-SameContent -Source $file.FullName -Target $target) {
      Write-Host "  [已一致] $($file.Name)"
    } elseif (Test-Path -LiteralPath $target) {
      Write-Host "  [待更新] $($file.Name)"
    } else {
      Write-Host "  [待复制] $($file.Name)"
    }
  }
  exit 0
}

# ---------------------------------------------------------------- 拷贝
if (-not (Test-Path -LiteralPath $Destination)) {
  Write-Step "创建目标目录 $Destination"
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

$copied = 0
$skipped = 0
foreach ($file in $files) {
  $target = Join-Path $Destination $file.Name
  if (Test-SameContent -Source $file.FullName -Target $target) {
    $skipped++
    Write-Step "$($file.Name) 内容一致，跳过"
    continue
  }

  Copy-Item -LiteralPath $file.FullName -Destination $target -Force
  $copied++
  Write-Step "$($file.Name) -> $target"
}

Write-Step "完成：拷贝 $copied 个，跳过 $skipped 个"
exit 0
