#Requires -Version 5.1
<#
  pwsh_keys — PowerShell 命令行键位（基于 PSReadLine）

    Ctrl+U  删除光标前（行首到光标）的所有内容
    Ctrl+K  删除光标后（光标到行尾）的所有内容

  这几行会写进"所有 host 共用"的 profile（CurrentUserAllHosts），
  所以 Windows Terminal / 控制台 / VS Code 等宿主都会生效：

    $PROFILE.CurrentUserAllHosts  ->  Documents\WindowsPowerShell\profile.ps1

  写入是幂等的：借助 helpers.ps1 的 WriteOnceToFile，同一行只写一次，
  setup.ps1 反复执行也不会重复写。

  用法:
    .\pwsh_keys.ps1                  # 写入（已存在的行会跳过）
    .\pwsh_keys.ps1 -List            # 只看状态，不做改动
    .\pwsh_keys.ps1 -Remove          # 从 profile 里移除这几行
    .\pwsh_keys.ps1 -ProfilePath x   # 写到指定的 profile 文件
#>

[CmdletBinding()]
param(
  # 要操作的 profile，默认 CurrentUserAllHosts（所有 host 共用）
  [string]$ProfilePath = $PROFILE.CurrentUserAllHosts,
  # 只显示状态，不做改动
  [switch]$List,
  # 从 profile 里移除这几行
  [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'helpers.ps1')

if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
  throw '拿不到 profile 路径，请用 -ProfilePath 显式指定'
}

# 原样写进 profile 的行
$KeyLines = @(
  "Set-PSReadLineKeyHandler -Chord 'Ctrl+u' -Function BackwardKillLine"
  "Set-PSReadLineKeyHandler -Chord 'Ctrl+k' -Function KillLine"
)

# ---------------------------------------------------------------- 只看状态
if ($List) {
  Write-Step "profile: $ProfilePath"
  foreach ($line in $KeyLines) {
    $exists = $false
    if (Test-Path -LiteralPath $ProfilePath) {
      $exists = @(Get-Content -LiteralPath $ProfilePath | Where-Object { $_ -ceq $line }).Count -gt 0
    }
    if ($exists) {
      Write-Host "  [已写入] $line"
    } else {
      Write-Host "  [未写入] $line"
    }
  }
  exit 0
}

# ---------------------------------------------------------------- 移除
if ($Remove) {
  if (-not (Test-Path -LiteralPath $ProfilePath)) {
    Write-Step 'profile 不存在，无需移除'
    exit 0
  }
  $original = @(Get-Content -LiteralPath $ProfilePath)
  $kept = @($original | Where-Object { $KeyLines -cnotcontains $_ })
  if ($kept.Count -eq $original.Count) {
    Write-Step 'profile 里没有本脚本写入的行，无需移除'
    exit 0
  }
  [System.IO.File]::WriteAllLines($ProfilePath, $kept, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
  Write-Step "已从 $ProfilePath 移除"
  exit 0
}

# ---------------------------------------------------------------- 写入
$written = 0
foreach ($line in $KeyLines) {
  if (WriteOnceToFile -Path $ProfilePath -Line $line) {
    $written++
    Write-Step "已写入: $line"
  } else {
    Write-Step "已存在，跳过: $line"
  }
}

if ($written -gt 0) {
  Write-Host '  新开一个 shell 生效，当前窗口可以先执行: . $PROFILE'
}
exit 0
