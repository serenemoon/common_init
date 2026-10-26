#Requires -Version 5.1
<#
  psmux — 把 common\ 下的 .psmux.conf 拷到用户根目录，并装好 ppm 插件

  psmux 是 Windows 上的 tmux，读用户根目录的 .psmux.conf：

    common\.psmux.conf  ->  %USERPROFILE%\.psmux.conf

  另外会确保 ppm 插件就位（只在不存在时装）：

    %USERPROFILE%\.psmux\plugins\ppm

  .psmux.conf 内容相同时跳过，ppm 已存在时跳过，所以重复执行没有副作用。

  安全阀：仓库里的源文件要是空的，默认不覆盖（免得把已有的配置清空），
  确实想覆盖再加 -Force。

  用法:
    .\psmux.ps1                      # 拷配置 + 装 ppm（已就绪的跳过）
    .\psmux.ps1 -List                # 只看状态，不做改动
    .\psmux.ps1 -Destination D:\x    # 换个“家目录”（默认用户根目录）
    .\psmux.ps1 -Force               # 源文件为空也照拷
#>

[CmdletBinding()]
param(
  # 拷到哪里，默认用户根目录（$HOME）；.psmux\plugins 也建在这里
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

$PluginName = 'ppm'
$PluginDir = Join-Path (Join-Path $Destination '.psmux\plugins') $PluginName
$PluginRepo = 'https://github.com/psmux/psmux-plugins.git'

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

# 装 ppm 插件：clone 到临时目录 -> 把 ppm 子目录烤进 .psmux\plugins -> 删临时目录
function Install-PpmPlugin {
  param([string]$PluginPath)

  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) {
    Write-Warn '没有找到 git，无法安装 ppm 插件'
    return $false
  }

  $pluginParent = Split-Path -Parent $PluginPath
  if (-not (Test-Path -LiteralPath $pluginParent)) {
    New-Item -ItemType Directory -Path $pluginParent -Force | Out-Null
  }

  $tempDir = Join-Path $env:TEMP 'psmux-plugins'
  # 上次失败可能留下目录，clone 到已存在的目录会报错
  if (Test-Path -LiteralPath $tempDir) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force
  }

  Write-Step "git clone $PluginRepo"
  & $git.Source clone $PluginRepo $tempDir | Out-Host
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "git clone 失败（退出码 $LASTEXITCODE）"
    return $false
  }

  try {
    $clonePlugin = Join-Path $tempDir $PluginName
    if (-not (Test-Path -LiteralPath $clonePlugin)) {
      Write-Warn "仓库里没有 $PluginName 目录：$clonePlugin"
      return $false
    }
    Copy-Item -LiteralPath $clonePlugin -Destination $PluginPath -Recurse -Force
    Write-Step "$PluginName -> $PluginPath"
    return $true
  } finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if (-not (Test-Path -LiteralPath $Source)) {
  Write-Warn "没有找到 $Source"
  exit 1
}

$sourceEmpty = (Get-Item -LiteralPath $Source).Length -eq 0
$same = Test-SameContent -SourcePath $Source -TargetPath $Target
$pluginReady = Test-Path -LiteralPath $PluginDir

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
  if ($pluginReady) {
    Write-Host "  [$PluginName 插件] 已安装（$PluginDir）"
  } else {
    Write-Host "  [$PluginName 插件] 未安装，会 clone 到 $PluginDir"
  }
  exit 0
}

# ---------------------------------------------------------------- 拷贝配置
if ($sourceEmpty -and -not $Force) {
  Write-Warn "源文件是空的：$Source"
  Write-Warn "为免把 $Target 覆盖成空文件，本次跳过；确实要覆盖就加 -Force"
  exit 1
}

if ($same) {
  Write-Step "$ConfigName 内容一致，跳过"
} else {
  $targetDir = Split-Path -Parent $Target
  if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
    Write-Step "创建目标目录 $targetDir"
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  }
  Copy-Item -LiteralPath $Source -Destination $Target -Force
  Write-Step "$ConfigName -> $Target"
}

# ---------------------------------------------------------------- ppm 插件
if ($pluginReady) {
  Write-Step "$PluginName 插件已安装（$PluginDir），跳过"
  exit 0
}

if (Install-PpmPlugin -PluginPath $PluginDir) {
  exit 0
}
exit 1
