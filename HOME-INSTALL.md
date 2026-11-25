# 家用安装（另一台机器）

本仓库是从 `JeffYu55/antigravity-armor` 拉下来、在本机跑通后回推的**可复现快照**：
除了上游代码，还包含三处针对实机环境的修正（见文末「与上游的差异」）。

---

## 0. 前置

| 项目 | 要求 |
|---|---|
| Node.js | **>= 20**（`node -v` 能看到；装完重开终端） |
| Antigravity | 已安装，**并且至少登录过一次**（有 `~/.gemini` 和有效 token） |
| Git | 任意 2.x |
| 网络 | 能直连 `daily-cloudcode-pa.googleapis.com` 与 `oauth2.googleapis.com` |

> 宿主**版本不必和这里一致**。脚本会读你机器的 `app.asar` 版本号、`language_server.exe` 的 size/sha256，自动改配置；没有对应补丁表时用旧表在你的二进制上重新派生（会打印 hit/miss 明细）。

---

## 1. 三步装完

```powershell
git clone https://github.com/Way2LOose4/Google-anti-.git
cd Google-anti-
powershell -ExecutionPolicy Bypass -File scripts\install-home.ps1
```

脚本会依次做：

1. 找 node（PATH → Program Files → workbuddy）
2. 找 Antigravity（`%LOCALAPPDATA%\Programs\antigravity` → 注册表 InstallLocation）
3. 读宿主版本 + `language_server.exe` 的 size / sha256
4. 改 `armor.config.json`（路径、expectedSize、expectedSha256）
5. 缺补丁表就 `derive-patches --emit` 生成 `patches/hosts/<版本>/binary-patches.json`
6. `install --apply`（binary / ide / rules / hooks 四层）
7. `armor reset` + `install --layer=rules --apply`（避免 purge 反复 DRIFT）
8. `divert start`（:50100）、`hud start`（:50101）、`hud shortcut`、`divert autostart install`
9. 打印 `status`

参数：

```powershell
-CheckOnly                               # 只探测不安装，先看环境对不对
-AntigravityRoot "D:\Apps\antigravity"   # 装到非默认位置时
-NodeExe "C:\Program Files\nodejs\node.exe"
-SkipServices                            # 只装文件，不起常驻进程
-NoAutostart                             # 不写登录自启计划任务
```

第一步永远先跑：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-home.ps1 -CheckOnly
```

它只读不写，打印 node 路径、宿主目录、宿主版本、`language_server.exe` 的 size/sha256、是否已破甲、补丁表是否存在。都对了再正式装。

> 脚本会检测二进制里有没有 `**[ARMOR v3]` 标记：**已破甲就不覆盖 config 里的原始指纹**（否则家里重装时 `assertHostShape` 会因为 sha 不匹配直接拒绝）。

---

## 2. 启动 IDE（关键，别双击原快捷方式）

装完后仓库里会有 `build\Antigravity-CDP.lnk`（由 `hud shortcut` 生成，带 `--remote-debugging-port=9222`）。

```powershell
# 先关掉所有 Antigravity 进程
Get-Process Antigravity*,language_server* -ErrorAction SilentlyContinue | Stop-Process -Force
# 再用带调试端口的快捷方式启动
Start-Process explorer.exe -ArgumentList "$PWD\build\Antigravity-CDP.lnk"
```

> 不要用 `Start-Process Antigravity.exe` 在脚本里直接拉——某些父进程（带 Job Object 的终端/IDE）会把它连带杀掉，表现为「进程闪一下就没、日志无新记录」。

IDE 起来后，注入齿轮：

```powershell
node src\cli.mjs hud attach
node scripts\check-gear-v2.mjs
```

看到 `"cls":"armed"` + `破甲已激活 · 宿主 <版本>` 就是好了。
齿轮颜色：🟢 armed 全效 / 🟡 warn 部分生效 / 🔴 off / ⚪ 未注入。

---

## 3. 验证与日常

```powershell
node src\cli.mjs status      # 六层概览
node src\cli.mjs verify      # 逐项自检（可加 --json）
node src\cli.mjs journal     # 最近判定的轨迹
```

期望值：

| 项 | 期望 |
|---|---|
| binary | ARMORED |
| ide | PATCHED -> localhost |
| rules / skill | 2/2 · present |
| hooks | 7 installed · scripts in sync |
| purge | ALIGNED v1.9.0 |
| divert | LISTENING :50100 **pass-through** |

`key KUAIPAOGLM_API_KEY MISSING` 这条警告在 `passThrough: true` / `sameModel: false` 下**可以忽略**：两条分支都在读 key 之前就返回了。

---

## 4. 回滚

```powershell
node src\cli.mjs rollback --layer=binary     # 从 state\backup 还原 language_server.exe
node src\cli.mjs rollback --layer=ide        # 还原 app.asar
node src\cli.mjs uninstall --apply           # 全撤（含 rules/hooks/计划任务）
```

备份在 `state\backup\`，文件名带时间戳。

---

## 5. 本次踩到的四个坑（已在本仓库修掉）

### 5.1 hooks 用裸 `node` → 对话报 `Invalid argument`

最贵的那个。`hooks.json` 里写的是 `node D:\...\xxx.cjs`，而宿主 PATH 里没有 node：

- hook 子进程直接 `exit 1`
- stderr 是 **GBK 中文**（`'node' 不是内部或外部命令…`）
- 这段字节被塞进 tool response
- Go 侧反序列化：`proto: invalid UTF-8 in string`
- 客户端 UI 折成：`Invalid argument: Agent execution terminated due to error`

**修法**：`src/layers/hooks.mjs` 的 `buildHooksJson()` 改用 `process.execPath`（当前 node 绝对路径）。`install-home.ps1` 会把本机 node 路径写进 7 个 hooks.json。
换 node 版本后要重跑 `node src\cli.mjs install --layer=hooks --apply`。

### 5.2 `sameModel: true` 换模型后只回 functionCall、0 正文

日志形态：

```
SAME-MODEL → SM-STRIP 自家装甲 → SM-RETRY chars=0
→ SM-MODEL gemini-4-neon-high -> gemini-3.8-flash-high
→ SM-DELIVER chars=0 finish=STOP toolCalls=1
→ VERDICT empty/transport
```

客户端拿到 0 字符正文 → 同样报 `Invalid argument`。
**修法**：`sameModel: false` + `passThrough: true`，改道只做透传，不换模型、不改写。

### 5.3 `maxAttempts: 1` 让第 0 档就砍上下文

`gemini-retry.mjs:1351` 的 `if (attempt >= maxAttempts - 1)` 在 `maxAttempts=1` 时对**第一次**请求就执行 `narrowContext`：

```
PASS-NARROW attempt=0 保留 2 条（丢 22 条）截断工具回包 15 处
```

工具调用上下文被砍断，agent 直接乱。
**修法**：`maxAttempts: 3`、`narrowKeepTurns: 8`、`narrowToolChars: 4000`。

### 5.4 purge 一直 DRIFT（bodyStale）

`hud` 每轮把 neutral 车道正文写进 `state\purge\armor-override.md`，于是 `sha16(armorBody)` 与戳里的 `armorHash` 对不上，`reapply.mjs:51` 的 `settled` 永远 false → 不打新戳，而且 ensure 每 5 分钟重写一次 rules。

**修法**：`armor reset`（丢弃 override，回 `assets/armor.md` 种子）+ `install --layer=rules --apply`。`install-home.ps1` 第 7 步已经内置。

---

## 6. 与上游的差异

| 文件 | 改动 | 原因 |
|---|---|---|
| `src/layers/hooks.mjs` | `buildHooksJson()` 用 `process.execPath` 代替 `'node '` | 宿主 PATH 无 node 时 hook 全崩，见 5.1 |
| `armor.config.json` | 路径/size/sha 指向本机；`passThrough:true`、`sameModel:false`、`maxAttempts:3`、`narrow*` 调宽 | 见 5.2 / 5.3 |
| `patches/hosts/2.35.1/binary-patches.json` | 新增（由 2.34.0 表在本机 2.35.1 上 derive，61 处生效 / 4 条 miss） | 上游只到 2.34.0 |
| `scripts/install-home.ps1`、`scripts/set-home-config.mjs`、`scripts/host-fingerprint.mjs` | 新增 | 换机器一条命令装完；指纹探测单独成脚本（PS 5.1 传 `-e` 会吃引号） |
| `aarmor.cmd` | 去掉硬编码 node 路径，改为多路探测 | 便携 |

> `state/`、`build/`、`*.bak-*` 不入库：前者是 400MB 运行时数据（含二进制备份和 token 抓包），后者是产物与图片。

---

## 7. 上游出处

原仓库：<https://github.com/JeffYu55/antigravity-armor>
本快照：<https://github.com/Way2LOose4/Google-anti->
