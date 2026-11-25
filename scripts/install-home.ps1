# armor 家用安装：自动探测本机 Antigravity / node，改 config，装四层，起服务。
# 用法（在仓库根目录）：
#   powershell -ExecutionPolicy Bypass -File scripts\install-home.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\install-home.ps1 -CheckOnly    # 只看探测结果
# 可选参数：
#   -AntigravityRoot "C:\Users\xxx\AppData\Local\Programs\antigravity"   手动指定宿主目录
#   -NodeExe "C:\Program Files\nodejs\node.exe"                          手动指定 node
#   -SkipServices                                                        只装文件，不常驻 divert/hud
#   -NoAutostart                                                         不装登录自启计划任务
param(
  [string]$AntigravityRoot = '',
  [string]$NodeExe = '',
  [switch]$SkipServices,
  [switch]$NoAutostart,
  [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Step($n, $msg) { Write-Host ''; Write-Host "[$n] $msg" -ForegroundColor Cyan }

# ---------- 1. node ----------
function Find-NodeExe([string]$Hint) {
  if ($Hint) {
    if (Test-Path $Hint) { return (Resolve-Path $Hint).Path }
    throw "指定的 node 不存在: $Hint"
  }
  $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $cands = @(
    (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe'),
    (Join-Path $env:APPDATA 'npm\node.exe')
  )
  $wb = Join-Path $env:USERPROFILE '.workbuddy\binaries\node\versions'
  if (Test-Path $wb) {
    Get-ChildItem $wb -Directory | Sort-Object Name -Descending |
      ForEach-Object { $cands = $cands + (Join-Path $_.FullName 'node.exe') }
  }
  foreach ($p in $cands) { if ($p -and (Test-Path $p)) { return $p } }
  throw '找不到 node.exe。请先装 Node.js 20+（https://nodejs.org），或用 -NodeExe 指定路径。'
}

# ---------- 2. Antigravity ----------
function Find-AntigravityRoot([string]$Hint) {
  if ($Hint) {
    if (Test-Path (Join-Path $Hint 'Antigravity.exe')) { return (Resolve-Path $Hint).Path }
    throw "指定目录里没有 Antigravity.exe: $Hint"
  }
  $cands = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\antigravity'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity'),
    (Join-Path $env:ProgramFiles 'Antigravity'),
    (Join-Path ${env:ProgramFiles(x86)} 'Antigravity')
  )
  foreach ($p in $cands) { if ($p -and (Test-Path (Join-Path $p 'Antigravity.exe'))) { return $p } }

  $keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  foreach ($k in $keys) {
    $hit = Get-ItemProperty $k -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -like '*Antigravity*' -and $_.InstallLocation } |
      ForEach-Object { $_.InstallLocation } |
      Where-Object { Test-Path (Join-Path $_ 'Antigravity.exe') } |
      Select-Object -First 1
    if ($hit) { return $hit }
  }
  throw '找不到 Antigravity 安装目录。请用 -AntigravityRoot "…\Programs\antigravity" 指定。'
}

# ---------- 3. 宿主指纹（版本 / 尺寸 / sha256 / 是否已破甲）----------
function Get-HostFingerprint($nodeExe, $root) {
  $json = (& $nodeExe (Join-Path $repo 'scripts\host-fingerprint.mjs') $root) -join "`n"
  $fp = $json | ConvertFrom-Json
  if ($fp.error) { throw $fp.error }
  return $fp
}

# ================= 开始 =================
Say '===== Antigravity armor · 家用安装 =====' 'Green'
Say "仓库: $repo"

Step 1 '定位 node'
$node = Find-NodeExe $NodeExe
$nodeVer = & $node -v
Say "  node   = $node ($nodeVer)"
if ([int]($nodeVer.TrimStart('v').Split('.')[0]) -lt 20) { throw "node 版本过低（需要 >= 20）：$nodeVer" }

Step 2 '定位 Antigravity'
$agRoot = Find-AntigravityRoot $AntigravityRoot
Say "  root   = $agRoot"

Step 3 '读取宿主版本与二进制指纹'
Say '  扫描 app.asar 与 language_server.exe（200MB 左右，几秒）…'
$fp = Get-HostFingerprint $node $agRoot
$ver = $fp.hostVersion
$lsExe = $fp.exe
$size = $fp.size
$sha = $fp.sha256
$armored = [bool]$fp.armored
$marker = $fp.marker
Say "  版本   = $ver"
Say "  LS     = $size B"
Say "  sha256 = $sha"

$writeSize = $size
$writeSha = $sha
if ($armored) {
  Say "  状态   = 已破甲（含 marker $marker）：保留 config 里的原始指纹，不覆盖" 'Yellow'
  Say '           要重装请先 node src\cli.mjs rollback --layer=binary' 'Yellow'
  $writeSize = ''
  $writeSha = ''
} else {
  Say '  状态   = 未打补丁（原始宿主）：用当前指纹写入 config'
}

Step 4 '写入 armor.config.json（路径 / 尺寸 / sha）'
$geminiHome = Join-Path $env:USERPROFILE '.gemini'
$dshHome = Join-Path $env:USERPROFILE '.dsh'

if ($CheckOnly) {
  $tableProbe = Join-Path $repo "patches\hosts\$ver\binary-patches.json"
  Say ''
  Say '===== 仅探测（-CheckOnly，未做任何改动）=====' 'Green'
  Say "  node            = $node ($nodeVer)"
  Say "  AntigravityRoot = $agRoot"
  Say "  宿主版本        = $ver"
  Say "  language_server = $size B"
  Say "  sha256          = $sha"
  Say "  已破甲          = $armored"
  Say "  geminiHome      = $geminiHome"
  Say "  补丁表          = $(if (Test-Path $tableProbe) { '已有 ' + $tableProbe } else { '缺，需要 derive' })"
  return
}

& $node (Join-Path $repo 'scripts\set-home-config.mjs') (Join-Path $repo 'armor.config.json') $agRoot $geminiHome $dshHome $writeSize $writeSha
if ($LASTEXITCODE -ne 0) { throw 'set-home-config 失败' }

Step 5 "确认 $ver 的补丁表"
$table = Join-Path $repo "patches\hosts\$ver\binary-patches.json"
if (Test-Path $table) {
  Say "  已有 $table"
} else {
  Say "  没有 $ver 的表，用旧表 + 本机宿主重新派生（hit/miss 会打印）" 'Yellow'
  & $node (Join-Path $repo 'scripts\derive-patches.mjs') --emit
  if ($LASTEXITCODE -ne 0) { throw 'derive-patches 失败' }
  if (-not (Test-Path $table)) {
    throw "派生后仍没有 $ver 的表：这个宿主版本可能改动过大，需要人工看一下 derive 的 miss 清单。"
  }
}

Step 6 '安装四层（binary / ide / rules / hooks）'
& $node (Join-Path $repo 'src\cli.mjs') install --apply
if ($LASTEXITCODE -ne 0) { throw 'install 失败' }

Step 7 '把规则正文重置成种子并重装（避免 purge 一直 DRIFT）'
& $node (Join-Path $repo 'src\cli.mjs') armor reset
& $node (Join-Path $repo 'src\cli.mjs') install --layer=rules --apply
if ($LASTEXITCODE -ne 0) { throw 'rules 重装失败' }

if (-not $SkipServices) {
  Step 8 '启动 divert（50100）与 HUD 控制面（50101）'
  & $node (Join-Path $repo 'src\cli.mjs') divert start
  & $node (Join-Path $repo 'src\cli.mjs') hud start
  & $node (Join-Path $repo 'src\cli.mjs') hud shortcut
  if (-not $NoAutostart) {
    & $node (Join-Path $repo 'src\cli.mjs') divert autostart install
  }
}

Step 9 '最终状态'
& $node (Join-Path $repo 'src\cli.mjs') status

Write-Host ''
Say '===== 装完了 =====' 'Green'
Say '下一步（手动）：'
Say '  1) 关掉所有 Antigravity 进程，用 build\Antigravity-CDP.lnk 启动（带 --remote-debugging-port=9222）'
Say '  2) IDE 起来后跑:  node src\cli.mjs hud attach     # 注入齿轮'
Say '  3) 齿轮变绿 = 破甲生效'
Say ''
Say '注意：hooks 会写入当前 node 的绝对路径。换 node 版本后重跑 install --layer=hooks --apply。'
