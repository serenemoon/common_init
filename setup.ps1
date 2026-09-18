#Requires -Version 5.1
<#
  Windows 初始化脚本

  步骤:
    choco            - 安装 chocolatey（已安装则跳过）
    build_essentials - 列出可安装的应用（cmake / make），选择安装
    gui              - 安装装机必选应用（notepad++ / obsidian / ultraedit / listary）

  用法:
    .\setup.ps1                     # 执行默认步骤，build essentials 会询问装哪些应用
    .\setup.ps1 -All                # 执行全部步骤，各步骤都安装全部应用（不再询问）
    .\setup.ps1 -NoBuildEssentials  # 跳过 build essentials
    .\setup.ps1 -NoGui              # 跳过装机必选应用
    .\setup.ps1 -List               # 只列出步骤状态和可安装的应用
#>

[CmdletBinding()]
param(
  [switch]$BuildEssentials,
  [switch]$NoBuildEssentials,
  [switch]$Gui,
  [switch]$NoGui,
  [switch]$All,
  [switch]$List,
  [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'windows/helpers.ps1')

$ChocoInstallUrl = 'https://community.chocolatey.org/install.ps1'
$BuildEssentialsScript = Join-Path $PSScriptRoot 'windows/build.ps1'
$GuiScript = Join-Path $PSScriptRoot 'windows/gui.ps1'

function Show-Usage {
  Write-Host @'
用法: .\setup.ps1 [选项]
  -BuildEssentials      启用 build essentials 步骤（默认启用）
  -NoBuildEssentials    跳过 build essentials 步骤
  -Gui                  启用装机必选应用步骤（默认启用）
  -NoGui                跳过装机必选应用步骤
  -All                  启用所有步骤，且每个步骤都安装全部应用（不再询问）
  -List                 只列出步骤状态和可安装的应用
  -Help                 显示本帮助
'@
}

function Install-Choco {
  Write-Step 'choco 未安装，开始安装'
  # 官方安装脚本要求 TLS 1.2
  [Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  Set-ExecutionPolicy Bypass -Scope Process -Force
  $installScript = (New-Object Net.WebClient).DownloadString($ChocoInstallUrl)
  Invoke-Expression $installScript
  Update-PathFromRegistry
  Write-Step 'choco 安装完成'
}

# 调用步骤脚本：-All 时不再询问，直接安装该步骤的全部应用
function Invoke-PackageStep {
  param(
    [string]$Path,
    [string]$Name,
    [switch]$InstallAll
  )

  if ($InstallAll) { & $Path -All } else { & $Path }
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "$Name 有应用安装失败，详见上方日志"
  }
}

# 提权重跑用：把当前命令行参数原样拼回去
function Get-RelaunchArguments {
  param(
    [hashtable]$BoundParameters,
    [string[]]$ExtraArgs = @()
  )

  $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
  foreach ($key in $BoundParameters.Keys) {
    $value = $BoundParameters[$key]
    if ($value -is [switch]) {
      if ($value.IsPresent) { $relaunchArgs += "-$key" }
    } else {
      # 数组参数用逗号拼，PowerShell 重新解析时会拆回数组
      $text = [string]$value
      if ($value -is [array]) { $text = $value -join ',' }
      $relaunchArgs += @("-$key", $text)
    }
  }
  return $relaunchArgs + $ExtraArgs
}

if ($Help) { Show-Usage; exit 0 }

# -- 步骤开关: 默认值，可用参数覆盖 ------------------------------------------
$EnableBuildEssentials = $true
if ($BuildEssentials) { $EnableBuildEssentials = $true }
if ($NoBuildEssentials) { $EnableBuildEssentials = $false } # 显式 -No 优先

$EnableGui = $true
if ($Gui) { $EnableGui = $true }
if ($NoGui) { $EnableGui = $false } # 显式 -No 优先

$chocoPath = Get-ChocoPath

if ($List) {
  Write-Host '步骤状态:'
  if ($chocoPath) {
    Write-Host "  choco            : 已安装 $(& $chocoPath --version)"
  } else {
    Write-Host '  choco            : 未安装'
  }
  Write-Host "  build_essentials : $([int]$EnableBuildEssentials)"
  Write-Host "  gui              : $([int]$EnableGui)"
  Write-Host ''
  & $BuildEssentialsScript -List
  Write-Host ''
  & $GuiScript -List
  exit 0
}

# choco 的安装需要管理员权限，非管理员时提权重跑
if (-not (Test-Admin)) {
  if (-not $PSCommandPath) {
    Write-Error '无法提权：请以文件方式运行本脚本，例如 powershell -ExecutionPolicy Bypass -File setup.ps1'
    exit 1
  }
  Write-Step '需要管理员权限，正在以管理员身份重新运行本脚本'
  $currentHost = (Get-Process -Id $PID).Path
  if (-not $currentHost) { $currentHost = 'powershell.exe' }
  $relaunchArgs = Get-RelaunchArguments -BoundParameters $PSBoundParameters -ExtraArgs $args
  Start-Process -FilePath $currentHost -Verb RunAs -ArgumentList $relaunchArgs
  exit 0
}

# -- 步骤 1: choco -----------------------------------------------------------
if ($chocoPath) {
  Write-Step "choco 已安装（$(& $chocoPath --version)），跳过"
} else {
  Install-Choco
  $chocoPath = Get-ChocoPathOrThrow
}

# -- 步骤 2: build essentials ------------------------------------------------
if ($EnableBuildEssentials) {
  Invoke-PackageStep -Path $BuildEssentialsScript -Name 'build essentials' -InstallAll:$All
} else {
  Write-Step 'build essentials 已跳过'
}

# -- 步骤 3: 装机必选应用 ---------------------------------------------------
if ($EnableGui) {
  Invoke-PackageStep -Path $GuiScript -Name '装机必选应用' -InstallAll:$All
} else {
  Write-Step '装机必选应用已跳过'
}
