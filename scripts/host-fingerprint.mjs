// 输出宿主指纹（JSON）：node scripts/host-fingerprint.mjs <antigravityRoot>
// 只做只读探测，供 install-home.ps1 / 人工排查使用。
// PowerShell 5.1 传 -e 内联脚本会被吃引号，所以把读取逻辑放这里，PS 只负责找路径。
import { readFileSync, existsSync, statSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { join } from 'node:path'

const root = process.argv[2]
if (!root) {
  console.error('usage: node scripts/host-fingerprint.mjs <antigravityRoot>')
  process.exit(2)
}

const out = {
  root,
  hostVersion: 'unknown',
  asar: null,
  exe: null,
  size: null,
  sha256: null,
  armored: false,
  marker: '**[ARMOR v3]',
  error: null,
}

try {
  const asar = join(root, 'resources', 'app.asar')
  if (existsSync(asar)) {
    out.asar = asar
    const txt = readFileSync(asar, 'utf8')
    const m = /"name"\s*:\s*"antigravity"/.exec(txt)
    if (m) {
      const seg = txt.slice(m.index, m.index + 400)
      const mv = /"version"\s*:\s*"([^"]+)"/.exec(seg)
      if (mv) out.hostVersion = mv[1]
    }
  }
  if (out.hostVersion === 'unknown') {
    const vf = join(root, 'resources', 'version')
    if (existsSync(vf)) {
      const v = readFileSync(vf, 'utf8').trim()
      if (v) out.hostVersion = v
    }
  }

  const exe = join(root, 'resources', 'bin', 'language_server.exe')
  if (!existsSync(exe)) throw new Error('language_server.exe 不存在: ' + exe)
  out.exe = exe
  out.size = statSync(exe).size

  const buf = readFileSync(exe)
  out.sha256 = createHash('sha256').update(buf).digest('hex').toUpperCase()
  out.armored = buf.includes(Buffer.from(out.marker, 'utf8'))
  out.size === buf.length // 触发一次性读取后释放
} catch (e) {
  out.error = String(e && e.message ? e.message : e)
}

process.stdout.write(JSON.stringify(out, null, 2))
