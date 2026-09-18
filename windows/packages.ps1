# 应用清单的展示 / 选择 / 安装流程，被 build.ps1、gui.ps1 复用
# 本文件只定义函数，不做任何实际操作

. (Join-Path $PSScriptRoot 'helpers.ps1')

# 应用已安装的说明文字，未安装则返回 $null
# 判断依据: choco 里装过这个包，或者 Probe（可执行文件路径，支持数组）已经存在
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
  $format = '  {0}) {1,-' + ($width + 2) + '} [{2}] {3}'

  Write-Host '可安装的应用:'
  for ($i = 0; $i -lt $Catalog.Count; $i++) {
    $item = $Catalog[$i]
    $status = Get-PackageStatus -Item $item -Installed $Installed
    if (-not $status) { $status = '未安装' }
    Write-Host ($format -f ($i + 1), $item.Name, $status, $item.Description)
  }
}

# 交互式选择，返回应用名数组（空数组表示什么都不装）
function Read-PackageSelection {
  param(
    [object[]]$Catalog,
    [hashtable]$Installed
  )

  Show-PackageCatalog -Catalog $Catalog -Installed $Installed
  Write-Host '  输入编号（多个用逗号分隔），a = 全部安装，直接回车 = 跳过'

  $answer = (Read-Host '请选择').Trim()
  if ([string]::IsNullOrWhiteSpace($answer)) { return @() }
  if ($answer -match '^(a|all)$') { return @($Catalog | ForEach-Object { $_.Name }) }

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

  $targets = @()
  foreach ($name in $Names) {
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
#   都不给         交互式选择
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
