#Requires -Version 5.1
<#
  Windows 初始化脚本

  先确保装好 chocolatey，然后列出可执行的步骤，让用户选要执行哪些。

    apps.ps1                      安装应用
    pwsh_keys.ps1                 配置命令行键位（Ctrl+U / Ctrl+K）
    fzf-for-windows-terminal.ps1  配置 fzf 快捷键（Ctrl+F / Ctrl+R / Alt+C）
    mkcd.ps1                      用 uv 装一套 Linux 命令（ls / cat / grep / tail ...）
    psmux.ps1                     把 common 下的 tmux 配置拷到用户目录

  用法:
    .\setup.ps1                 # 交互选择步骤（默认都不执行，y = 全部执行）
    .\setup.ps1 -Steps 2        # 只执行第 2 步
    .\setup.ps1 -Steps pwsh_keys,fzf
    .\setup.ps1 -List           # 只看状态，不做改动
    .\setup.ps1 -Help           # 显示本帮助
#>

[CmdletBinding()]
param(
  # 只执行指定步骤（编号或名字，多个用逗号分隔）；不给就交互选择
  [string[]]$Steps = @(),
  # 只列出步骤状态和应用清单，不做任何改动
  [switch]$List,
  [switch]$Help,
  # `--` 之后的所有参数，原样透传给被执行的步骤脚本
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$StepArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'windows/helpers.ps1')

$ChocoInstallUrl = 'https://community.chocolatey.org/install.ps1'

# 可执行的步骤，按这个顺序执行；要加新步骤在这张表里加一行即可
$StepTable = @(
  [pscustomobject]@{
    Name = 'apps'
    Script = 'windows/apps.ps1'
    Description = '安装应用'
  }
  [pscustomobject]@{
    Name = 'pwsh_keys'
    Script = 'windows/pwsh_keys.ps1'
    Description = '配置命令行键位（Ctrl+U / Ctrl+K）'
  }
  [pscustomobject]@{
    Name = 'fzf'
    Script = 'windows/fzf-for-windows-terminal.ps1'
    Description = '配置 fzf 快捷键（Ctrl+F / Ctrl+R / Alt+C）'
  }
  [pscustomobject]@{
    Name = 'mkcd'
    Script = 'windows/mkcd.ps1'
    Description = '用 uv 装一套 Linux 命令（需要 uv）'
  }
  [pscustomobject]@{
    Name = 'psmux'
    Script = 'windows/psmux.ps1'
    Description = '拷 tmux 配置到用户目录'
  }
)

function Show-Usage {
  Write-Host @'
用法: .\setup.ps1 [选项]
  -Steps <编号或名字>  只执行指定步骤，多个用逗号分隔
                       例: -Steps 2    -Steps pwsh_keys,fzf
                       不给这个参数时交互选择（回车 = 都不执行，y = 全部）
  -List                只列出步骤状态和应用清单，不做任何改动
  -Help                显示本帮助
  -- <参数...>         `--` 后面的参数原样传给被执行的步骤脚本（选多个步骤时都会收到）
                         例: .\setup.ps1 -Steps psmux -- -Destination D:\x
'@
}

# 列出步骤菜单，形如: [ 1]: apps.ps1  "安装应用"
function Show-StepMenu {
  param([object[]]$StepTable)

  $width = 0
  foreach ($step in $StepTable) {
    $file = Split-Path -Leaf $step.Script
    if ($file.Length -gt $width) { $width = $file.Length }
  }
  $format = '[{0,2}]: {1,-' + ($width + 1) + '} "{2}"'

  Write-Host '可执行的步骤:'
  for ($i = 0; $i -lt $StepTable.Count; $i++) {
    $step = $StepTable[$i]
    Write-Host ($format -f ($i + 1), (Split-Path -Leaf $step.Script), $step.Description)
  }
}

# 交互式选择步骤，返回选中的步骤（空数组表示什么都不执行）
function Read-StepSelection {
  param([object[]]$StepTable)

  Show-StepMenu -StepTable $StepTable
  Write-Host '  输入编号（多个用逗号分隔）= 只执行这几个，y = 全部执行，n 或直接回车 = 都不执行'

  $answer = Read-Host '请选择'
  # 直接回车（含非交互场景下 Read-Host 返回 $null）= 什么都不执行
  if ([string]::IsNullOrWhiteSpace($answer)) { return @() }
  $answer = $answer.Trim()
  if ($answer -match '^(y|yes|a|all)$') { return @($StepTable) }
  if ($answer -match '^(n|no)$') { return @() }

  return @(Resolve-StepSelection -StepTable $StepTable -Tokens @($answer))
}

# 把编号 / 名字 / 脚本文件名解析成步骤，未知的忽略
function Resolve-StepSelection {
  param(
    [object[]]$StepTable,
    [string[]]$Tokens
  )

  $selected = New-Object System.Collections.Generic.List[object]
  foreach ($raw in $Tokens) {
    foreach ($token in ($raw -split '[,;\s]+')) {
      if (-not $token) { continue }

      $index = 0
      $match = $null
      if ([int]::TryParse($token, [ref]$index)) {
        if ($index -ge 1 -and $index -le $StepTable.Count) { $match = $StepTable[$index - 1] }
      } else {
        $match = $StepTable | Where-Object {
          $_.Name -eq $token -or
          (Split-Path -Leaf $_.Script) -eq $token -or
          [System.IO.Path]::GetFileNameWithoutExtension($_.Script) -eq $token
        } | Select-Object -First 1
      }

      if (-not $match) {
        Write-Warn "忽略无法识别的步骤: $token"
        continue
      }
      if (-not ($selected | Where-Object { $_.Name -eq $match.Name })) {
        $selected.Add($match)
      }
    }
  }
  # 注意：这里不能写成 @($selected)，PS 5.1 在 StrictMode 下对泛型 List 用 @() 会抛
  # ArgumentException（参数类型不匹配）
  return $selected.ToArray()
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

# 把透传参数拼回命令行再执行。
# 数组 splat（@args）会把 "-Name value" 当成位置参数，只有重新过一遍解析器，
# 语义才和用户直接敲命令一致（开关 / -Name value / 带空格的值）。
function Invoke-StepScript {
  param(
    [string]$Path,
    [string[]]$Arguments = @()
  )

  if ($Arguments.Count -eq 0) {
    & $Path
    return
  }

  $command = "& '" + ($Path -replace "'", "''") + "'"
  foreach ($argument in $Arguments) {
    if ($argument -match '[\s''"]') {
      $command += " '" + ($argument -replace "'", "''") + "'"
    } else {
      $command += ' ' + $argument
    }
  }
  Invoke-Expression $command
}

if ($Help) { Show-Usage; exit 0 }

# `--` 后面的参数透传给步骤脚本。PowerShell 一般会把 `--` 自己吃掉，
# 这里再兜一下：万一它作为参数传进来，就跳过。
$PassThru = @()
if ($StepArgs.Count -gt 0) {
  $start = 0
  if ($StepArgs[0] -eq '--') { $start = 1 }
  if ($StepArgs.Count -gt $start) {
    $PassThru = @($StepArgs[$start..($StepArgs.Count - 1)])
  }
}

$chocoPath = Get-ChocoPath

if ($List) {
  if ($chocoPath) {
    Write-Host "choco : 已安装 $(& $chocoPath --version)"
  } else {
    Write-Host 'choco : 未安装'
  }
  Write-Host ''
  Show-StepMenu -StepTable $StepTable
  foreach ($step in $StepTable) {
    Write-Host ''
    & (Join-Path $PSScriptRoot $step.Script) -List
  }
  exit 0
}

# choco 的安装需要管理员权限，非管理员时提权重跑。
# 放在交互选择之前，免得提权后又问一遍。
if (-not (Test-Admin)) {
  if (-not $PSCommandPath) {
    Write-Error '无法提权：请以文件方式运行本脚本，例如 powershell -ExecutionPolicy Bypass -File setup.ps1'
    exit 1
  }
  Write-Step '需要管理员权限，正在以管理员身份重新运行本脚本'
  $currentHost = (Get-Process -Id $PID).Path
  if (-not $currentHost) { $currentHost = 'powershell.exe' }
  # 透传参数单独拼，别经过 Get-RelaunchArguments 的逗号拼接
  $boundParameters = @{}
  foreach ($key in $PSBoundParameters.Keys) {
    if ($key -eq 'StepArgs') { continue }
    $boundParameters[$key] = $PSBoundParameters[$key]
  }
  $extraArgs = @()
  if ($PassThru.Count -gt 0) { $extraArgs = @('--') + $PassThru }
  $relaunchArgs = Get-RelaunchArguments -BoundParameters $boundParameters -ExtraArgs $extraArgs
  Start-Process -FilePath $currentHost -Verb RunAs -ArgumentList $relaunchArgs
  exit 0
}

# -- 步骤 0: choco -----------------------------------------------------------
if ($chocoPath) {
  Write-Step "choco 已安装（$(& $chocoPath --version)），跳过"
} else {
  Install-Choco
  $chocoPath = Get-ChocoPathOrThrow
}

# -- 选择要执行的步骤 --------------------------------------------------------
if ($Steps.Count -gt 0) {
  $selected = @(Resolve-StepSelection -StepTable $StepTable -Tokens $Steps)
} else {
  $selected = @(Read-StepSelection -StepTable $StepTable)
}

if ($selected.Count -eq 0) {
  Write-Step '没有选择任何步骤，退出'
  exit 0
}

# -- 按顺序执行选中的步骤 ----------------------------------------------------
if ($PassThru.Count -gt 0) {
  Write-Step "透传参数: $($PassThru -join ' ')"
}

foreach ($step in $StepTable) {
  if (-not ($selected | Where-Object { $_.Name -eq $step.Name })) {
    Write-Step "跳过 $($step.Name)"
    continue
  }

  $path = Join-Path $PSScriptRoot $step.Script
  Write-Step "执行 $($step.Name)（$(Split-Path -Leaf $path)）"
  Invoke-StepScript -Path $path -Arguments $PassThru
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "$($step.Name) 执行失败，详见上方日志"
  }
}
