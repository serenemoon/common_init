# 公共函数，被 setup.ps1 和 windows/*.ps1 用 dot-source 引入
# 本文件只定义函数，不做任何实际操作

function Write-Step {
  param([string]$Message)
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Warn {
  param([string]$Message)
  Write-Host "!!! $Message" -ForegroundColor Yellow
}

function Test-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 把机器级和用户级的 PATH 重新读一遍，覆盖当前会话
function Update-PathFromRegistry {
  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = @($machinePath, $userPath | Where-Object { $_ }) -join ';'
}

# 返回 choco 可执行文件路径，未安装则返回 $null
function Get-ChocoPath {
  $cmd = Get-Command choco -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  # 装在默认目录，但当前会话 PATH 里还没有
  $defaultChoco = Join-Path $env:ProgramData 'chocolatey\bin\choco.exe'
  if (Test-Path -LiteralPath $defaultChoco) { return $defaultChoco }

  return $null
}

# 返回 choco 可执行文件路径，未安装则报错
function Get-ChocoPathOrThrow {
  $chocoPath = Get-ChocoPath
  if (-not $chocoPath) {
    throw 'choco 未安装，请先运行 setup.ps1'
  }
  return $chocoPath
}

# 返回本机已安装的 choco 包，形如 @{ cmake = '4.3.1' }
function Get-ChocoInstalledPackages {
  $packages = @{}
  $chocoPath = Get-ChocoPath
  if (-not $chocoPath) { return $packages }

  # --limit-output 输出 name|version，不带版本横幅
  foreach ($line in (& $chocoPath list --local-only --limit-output)) {
    $parts = $line -split '\|', 2
    if ($parts.Count -eq 2) {
      $packages[$parts[0].Trim()] = $parts[1].Trim()
    }
  }
  return $packages
}
