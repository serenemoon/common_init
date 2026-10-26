#Requires -Version 5.1
<#
  psmux — 把 common\ 下的 .psmux.conf 拷到用户根目录

  psmux 是 Windows 上的 tmux，读用户根目录的 .psmux.conf：

    common\.psmux.conf  ->  %USERPROFILE%\.psmux.conf

  内容相同时跳过，所以重复执行没有副作用。

  安全阀：仓库里的源文件要是空的，默认不覆盖（免得把已有的配置清空），
  确实想覆盖再加 -Force。

  用法:
    .\psmux.ps1                      # 拷贝（已一致时跳过）
    .\psmux.ps1 -List                # 只看状态，不做改动
    .\psmux.ps1 -Destination D:\x    # 拷到指定目录（默认用户根目录）
    .\psmux.ps1 -Force               # 源文件为空也照拷
#>

[CmdletBinding()]
param(
  # 拷到哪里，默认用户根目录（$HOME）
  [string]$Destination = $HOME,
  # 只看状态，不做改动
  [switch]$List,
  # 源文件为空时也照拷（默认会拒绝，避免清空已有配置）
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'helpers.ps1')

$ConfigName = '.psmux.conf'
$CommonDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'common'
$Source = Join-Path $CommonDir $ConfigName
if ([string]::IsNullOrWhiteSpace($Destination)) { $Destination = $HOME }
$Target = Join-Path $Destination $ConfigName

# 两个文件内容是否一致；目标不存在时返回 $false
function Test-SameContent {
  param(
    [string]$SourcePath,
    [string]$TargetPath
  )

  if (-not (Test-Path -LiteralPath $TargetPath)) { return $false }
  $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
  $targetHash = (Get-FileHash -LiteralPath $TargetPath -Algorithm SHA256).Hash
  return $sourceHash -eq $targetHash
}

if (-not (Test-Path -LiteralPath $Source)) {
  Write-Warn "没有找到 $Source"
  exit 1
}

$sourceEmpty = (Get-Item -LiteralPath $Source).Length -eq 0
$same = Test-SameContent -SourcePath $Source -TargetPath $Target

# ---------------------------------------------------------------- 只看状态
if ($List) {
  Write-Step "源文件  : $Source"
  Write-Step "目标文件: $Target"
  if ($same) {
    Write-Host "  [已一致] $ConfigName"
  } elseif (Test-Path -LiteralPath $Target) {
    Write-Host "  [待更新] $ConfigName"
  } else {
    Write-Host "  [待复制] $ConfigName"
  }
  if ($sourceEmpty) {
    Write-Host '  [注意] 源文件是空的（0 字节），默认不会覆盖目标'
  }
  exit 0
}

# ---------------------------------------------------------------- 拷贝
if ($sourceEmpty -and -not $Force) {
  Write-Warn "源文件是空的：$Source"
  Write-Warn "为免把 $Target 覆盖成空文件，本次跳过；确实要覆盖就加 -Force"
  exit 1
}

if ($same) {
  Write-Step "$ConfigName 内容一致，跳过"
  exit 0
}

$targetDir = Split-Path -Parent $Target
if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
  Write-Step "创建目标目录 $targetDir"
  New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Copy-Item -LiteralPath $Source -Destination $Target -Force
Write-Step "$ConfigName -> $Target"
exit 0
