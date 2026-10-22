#Requires -Version 5.1
<#
  mkcd — 在 Windows 上用 uv 装一套 Linux 命令（ls / cat / grep / tail / tar ...）

  参考 https://pypi.org/project/mkcd/ ，安装流程是：

    1. 在 D:\.mkcd 建 uv 环境，并用 uv 把 Python 3.14 装进这个目录
    2. uv pip install mkcd
    3. uv run python -c "import mkcd; mkcd.install()" 完成注册

  第 3 步会把 mkcd 的命令目录加进 PATH，并清掉冲突的 PowerShell 别名
  （ls / cat / rm / pwd ...）；它还会问要不要用管理员权限改系统 PATH，
  不同意就退化成只改用户 PATH。装完要新开一个终端才生效。

  联网的 uv 命令都带 --system-certs：uv 默认只信内置的 Mozilla 根证书，不读
  Windows 证书存储，碰到公司网络的 TLS 解密代理（如 Zscaler）会报
  "invalid peer certificate: UnknownIssuer"。带上这个开关就改用系统证书
  （uv 0.13 起 --native-tls 已弃用，改名成 --system-certs）。

  前提: uv（在 apps.ps1 的清单里，setup.ps1 选步骤 1 时勾上 uv）

  用法:
    .\mkcd.ps1                       # 建环境 + 装 mkcd + 跑安装器
    .\mkcd.ps1 -List                 # 只看状态，不做改动
    .\mkcd.ps1 -Force                # 已装过也重来一遍（含 mkcd.install()）
    .\mkcd.ps1 -EnvDir E:\.mkcd -Python 3.13
#>

[CmdletBinding()]
param(
  # uv 环境放在哪（Python 和 venv 都在这个目录下）
  [string]$EnvDir = 'D:\.mkcd',
  # 要用哪个 Python 版本
  [string]$Python = '3.14',
  # 只看状态，不做改动
  [switch]$List,
  # 即使已经装过也重新执行
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'helpers.ps1')

$PythonDir = Join-Path $EnvDir 'python'
$VenvDir = Join-Path $EnvDir '.venv'
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
$SitePackages = Join-Path $VenvDir 'Lib\site-packages'
$MkcdBin = Join-Path $SitePackages 'mkcd\_bin\windows_x86_64'

# 在 $PythonDir 里找 uv 装下的 python.exe（布局是 cpython-3.14.x-windows-x86_64-none\python.exe）
function Get-LocalPython {
  param([string]$Dir)

  if (-not (Test-Path -LiteralPath $Dir)) { return $null }
  $found = @(Get-ChildItem -LiteralPath $Dir -Filter 'python.exe' -Recurse -File -ErrorAction SilentlyContinue)
  if ($found.Count -eq 0) { return $null }

  # 优先挑 x86_64 的那个，避免命中别的构建
  foreach ($item in $found) {
    if ($item.FullName -match 'windows[^\\]*x86_64') { return $item.FullName }
  }
  return $found[0].FullName
}

# 从 pyvenv.cfg 里读 venv 的 Python 版本
function Get-VenvVersion {
  param([string]$Dir)

  $cfg = Join-Path $Dir 'pyvenv.cfg'
  if (-not (Test-Path -LiteralPath $cfg)) { return $null }
  foreach ($line in (Get-Content -LiteralPath $cfg)) {
    if ($line -match '^\s*version_info\s*=\s*(.+)$') { return $Matches[1].Trim() }
  }
  return $null
}

# 从 site-packages 里的 dist-info 目录名读包版本
function Get-PackageVersion {
  param(
    [string]$Dir,
    [string]$Name
  )

  if (-not (Test-Path -LiteralPath $Dir)) { return $null }
  $infos = @(Get-ChildItem -LiteralPath $Dir -Filter "$Name-*.dist-info" -Directory -ErrorAction SilentlyContinue)
  if ($infos.Count -eq 0) { return $null }
  if ($infos[0].Name -match "^$([regex]::Escape($Name))-(.+)\.dist-info$") { return $Matches[1] }
  return '已安装'
}

# 某个目录是否已经在 PATH 里（用户级、系统级、当前会话任一命中就算）
function Test-OnPath {
  param([string]$Directory)

  $target = $Directory.TrimEnd('\')
  $sources = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine')
    [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path
  )
  foreach ($source in $sources) {
    if (-not $source) { continue }
    foreach ($entry in ($source -split ';')) {
      if ($entry -and $entry.TrimEnd('\') -ieq $target) { return $true }
    }
  }
  return $false
}

$uv = Get-Command uv -ErrorAction SilentlyContinue
$uvVersion = $null
if ($uv) { $uvVersion = (& $uv.Source --version) }

# ---------------------------------------------------------------- 只看状态
if ($List) {
  if ($uvVersion) {
    Write-Step "uv        : 已安装 $uvVersion"
  } else {
    Write-Step 'uv        : 未安装（先装 uv：.\setup.ps1 -Steps 1 里选 uv）'
  }
  Write-Step "环境目录  : $EnvDir"

  $pyExe = Get-LocalPython -Dir $PythonDir
  if ($pyExe) {
    Write-Host "  python    : $pyExe"
  } else {
    Write-Host "  python    : 未安装（会在 $PythonDir 里装 Python $Python）"
  }

  if (Test-Path -LiteralPath $VenvPython) {
    $venvVer = Get-VenvVersion -Dir $VenvDir
    if ($venvVer) {
      Write-Host "  venv      : 已创建（Python $venvVer）"
    } else {
      Write-Host '  venv      : 已创建'
    }
  } else {
    Write-Host "  venv      : 未创建（$VenvDir）"
  }

  $pkgVersion = Get-PackageVersion -Dir $SitePackages -Name 'mkcd'
  if ($pkgVersion) {
    Write-Host "  mkcd 包   : 已安装 $pkgVersion"
  } else {
    Write-Host '  mkcd 包   : 未安装'
  }

  if (Test-OnPath -Directory $MkcdBin) {
    Write-Host '  命令      : 已注册（PATH 里有 mkcd 的命令目录）'
  } else {
    Write-Host '  命令      : 未注册（需要跑 mkcd.install()）'
  }
  exit 0
}

# ---------------------------------------------------------------- 安装
if (-not $uv) {
  Write-Warn '没有找到 uv，请先安装：.\setup.ps1 -Steps 1 里选 uv（或 choco install uv）'
  exit 1
}

if (-not (Test-Path -LiteralPath $EnvDir)) {
  Write-Step "创建环境目录 $EnvDir"
  New-Item -ItemType Directory -Path $EnvDir -Force | Out-Null
}

# -- 1. Python ---------------------------------------------------------------
$pyExe = Get-LocalPython -Dir $PythonDir
if ($pyExe -and -not $Force) {
  Write-Step "Python 已安装在 $PythonDir，跳过"
} else {
  Write-Step "用 uv 安装 Python $Python 到 $PythonDir"
  & $uv.Source python install $Python --install-dir $PythonDir --system-certs | Out-Host
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "Python $Python 安装失败（uv 退出码 $LASTEXITCODE）"
    exit 1
  }
  $pyExe = Get-LocalPython -Dir $PythonDir
  if (-not $pyExe) {
    Write-Warn "装完了但在 $PythonDir 里找不到 python.exe"
    exit 1
  }
}

# -- 2. venv ----------------------------------------------------------------
if ((Test-Path -LiteralPath $VenvPython) -and -not $Force) {
  Write-Step "venv 已存在（$(Get-VenvVersion -Dir $VenvDir)），跳过"
} else {
  Write-Step "创建 venv: $VenvDir"
  & $uv.Source venv $VenvDir --python $pyExe | Out-Host
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $VenvPython)) {
    Write-Warn 'venv 创建失败'
    exit 1
  }
}

# -- 3. 装 mkcd 包 -----------------------------------------------------------
Write-Step '安装 mkcd 包（uv pip install mkcd）'
& $uv.Source pip install --python $VenvPython --system-certs mkcd | Out-Host
if ($LASTEXITCODE -ne 0) {
  Write-Warn "mkcd 安装失败（uv 退出码 $LASTEXITCODE）"
  exit 1
}

# -- 4. 跑安装器 -------------------------------------------------------------
# mkcd.install() 是幂等的，但会问一次管理员权限，已经在 PATH 里就别再问
if ((Test-OnPath -Directory $MkcdBin) -and -not $Force) {
  Write-Step 'PATH 里已经有 mkcd 的命令目录，跳过 mkcd.install()'
} else {
  Write-Step '执行 mkcd.install()（可能会问是否用管理员权限改系统 PATH）'
  Push-Location $EnvDir
  try {
    # --system-certs 必须放在 python 之前，后面的参数会原样传给 python
    & $uv.Source run --no-project --system-certs python -c 'import mkcd; mkcd.install()' | Out-Host
    $installExit = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  if ($installExit -ne 0) {
    Write-Warn "mkcd.install() 失败（退出码 $installExit）"
    exit 1
  }
}

Write-Step '完成：新开一个终端后就能用 ls / cat / grep / tail 等命令了'
exit 0
