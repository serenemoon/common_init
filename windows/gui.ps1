#Requires -Version 5.1
<#
  安装装机必选的应用

  用法:
    .\gui.ps1                     # 列出应用，交互式选择
    .\gui.ps1 -All                # 安装全部应用
    .\gui.ps1 -Packages obsidian  # 只安装指定应用
    .\gui.ps1 -List               # 只列出应用，不安装
    .\gui.ps1 -All -Force         # 全部重新安装（包括已安装的）
#>

[CmdletBinding()]
param(
  # 要安装的应用名，如 obsidian
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

# 装机必选应用清单，新增工具在这里加一行即可
$Catalog = @(
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

if ($List) {
  Show-PackageCatalog -Catalog $Catalog -Installed (Get-ChocoInstalledPackages)
  exit 0
}

$failed = @(Install-PackageCatalog -Catalog $Catalog -Packages $Packages -All:$All -Force:$Force)

if ($failed.Count -gt 0) {
  Write-Warn "以下应用安装失败: $($failed -join ', ')"
  exit 1
}
Write-Step '装机必选应用处理完成'
exit 0
