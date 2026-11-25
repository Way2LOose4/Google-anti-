# armor 家用安装：自动探测本机 Antigravity / node，改 config，装六层，起服务。
# 用法（在仓库根目录）：
#   powershell -ExecutionPolicy Bypass -File scripts\install-home.ps1
# 可选参数：
#   -AntigravityRoot "C:\Users\xxx\AppData\Local\Programs\antigravity"   手动指定宿主目录
#   -NodeExe "C:\Program Files\nodejs\node.exe"                          手动指定 node
#   -SkipServices                                                        只装文件，不常驻 divert/hud
#   -NoAutostart                                                         不装登录自启计划任务
param(
  [string]$AntigravityRoot = '',
  [string]$NodeExe = '',
  [switch]$SkipServices,
  [switch]$NoAutostart
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
    (Join-Path $env:USERPROFILE 'AppData\Roaming\npm\node.exe')
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

# ---------- 3. 宿主版本 ----------
function Get-HostVersion([string]$root) {
  $asar = Join-Path $root 'resources\app.asar'
  if (Test-Path $asar) {
    $txt = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($asar))
    $m = [regex]::Match($txt, '"name"\s*:\s*"antigravity"')
    if ($m.Success) {
      $len = [Math]::Min(400, $txt.Length - $m.Index)
      $mv = [regex]::Match($txt.Substring($m.Index, $len), '"version"\s*:\s*"([^"]+)"')
      if ($mv.Success) { return $mv.Groups[1].Value }
    }
  }
  $vf = Join-Path $root 'resources\version'
  if (Test-Path $vf) {
    $v = (Get-Content $vf -Raw).Trim()
    if ($v) { return $v }
  }
  return 'unknown'
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
$ver = Get-HostVersion $agRoot
$lsExe = Join-Path $agRoot 'resources\bin\language_server.exe'
if (-not (Test-Path $lsExe)) { throw "找不到 $lsExe" }
$size = (Get-Item $lsExe).Length
Say "  版本   = $ver"
Say "  LS     = $size B"
Say '  正在算 sha256（200MB 左右，几秒）…'
$sha = (Get-FileHash $lsExe -Algorithm SHA256).Hash
Say "  sha256 = $sha"

Step 4 '写入 armor.config.json（路径 / 尺寸 / sha）'
$geminiHome = Join-Path $env:USERPROFILE '.gemini'
$dshHome = Join-Path $env:USERPROFILE '.dsh'
& $node (Join-Path $repo 'scripts\set-home-config.mjs') (Join-Path $repo 'armor.config.json') $agRoot $geminiHome $dshHome $size $sha
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

Step 6 '安装六层（binary / ide / rules / hooks）'
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
Say '注意：hooks 用当前 node 的绝对路径写进 hooks.json。换 node 版本后重跑本脚本或 install --layer=hooks --apply。'
