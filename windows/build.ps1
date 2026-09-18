#Requires -Version 5.1
<#
  安装 Windows 上的构建基础工具

  用法:
    .\build.ps1                  # 列出应用，交互式选择
    .\build.ps1 -All             # 安装全部应用
    .\build.ps1 -Packages cmake  # 只安装指定应用
    .\build.ps1 -List            # 只列出应用，不安装
    .\build.ps1 -All -Force      # 全部重新安装（包括已安装的）
#>

[CmdletBinding()]
param(
  # 要安装的应用名，如 cmake,make
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

. (Join-Path $PSScriptRoot 'packages.ps1')

# 可安装的应用清单，新增工具在这里加一行即可
$Catalog = @(
  [pscustomobject]@{ Name = 'cmake'; ChocoId = 'cmake'; Description = 'CMake 跨平台构建系统' }
  [pscustomobject]@{ Name = 'make';  ChocoId = 'make';  Description = 'GNU make' }
)

if ($List) {
  Show-PackageCatalog -Catalog $Catalog -Installed (Get-ChocoInstalledPackages)
  exit 0
}

$failed = @(Install-PackageCatalog -Catalog $Catalog -Packages $Packages -All:$All -Force:$Force)

if ($failed.Count -gt 0) {
  Write-Warn "以下应用安装失败: $($failed -join ', ')"
  exit 1
}
Write-Step 'build essentials 处理完成'
exit 0
