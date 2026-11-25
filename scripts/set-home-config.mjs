// 把 armor.config.json 里跟「这台机器」绑定的字段改成本机值。
// 用法：node scripts/set-home-config.mjs <config> <antigravityRoot> <geminiHome> <dshHome> <size> <sha256>
// 只用 node 读写，避免 PowerShell 在 GBK 控制台下把中文 prefill 写成乱码。
import { readFileSync, writeFileSync, existsSync, copyFileSync } from 'node:fs'

const [, , cfgPath, agRoot, geminiHome, dshHome, size, sha] = process.argv
if (!cfgPath || !agRoot) {
  console.error('usage: node scripts/set-home-config.mjs <config> <antigravityRoot> <geminiHome> <dshHome> <size> <sha256>')
  process.exit(2)
}
if (!existsSync(cfgPath)) {
  console.error('config not found: ' + cfgPath)
  process.exit(2)
}

const raw = readFileSync(cfgPath, 'utf8')
const j = JSON.parse(raw)
const before = JSON.stringify(j)

j.paths = j.paths || {}
j.paths.antigravityRoot = agRoot
if (geminiHome) j.paths.geminiHome = geminiHome
if (dshHome) j.paths.dshHome = dshHome

j.binary = j.binary || {}
if (size) j.binary.expectedSize = Number(size)
if (sha) j.binary.expectedSha256 = String(sha).toUpperCase()

const after = JSON.stringify(j)
if (after === before) {
  console.log('config: 无需改动')
  process.exit(0)
}

const stamp = new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 14)
const bak = cfgPath + '.bak-' + stamp
copyFileSync(cfgPath, bak)
writeFileSync(cfgPath, JSON.stringify(j, null, 2) + '\n', 'utf8')
console.log('config: 已更新（备份 ' + bak + '）')
console.log('  antigravityRoot = ' + j.paths.antigravityRoot)
console.log('  geminiHome      = ' + j.paths.geminiHome)
console.log('  dshHome         = ' + j.paths.dshHome)
console.log('  expectedSize    = ' + j.binary.expectedSize)
console.log('  expectedSha256  = ' + j.binary.expectedSha256)
