import { createHash } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'

export const sha256 = (data) => createHash('sha256').update(data).digest('hex')

export const readCompiler = (dir) => JSON.parse(fs.readFileSync(path.join(dir, 'compiler.json'), 'utf8'))

export function listSources(dir) {
  const root = path.join(dir, 'sources')
  return fs
    .readdirSync(root, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => path.relative(root, path.join(entry.parentPath, entry.name)).split(path.sep).join('/'))
    .sort()
}

export function checkSources(dir) {
  const { sourceHashes } = readCompiler(dir)
  const found = new Set(listSources(dir))
  const changed = [...found].filter(
    (file) =>
      !(file in sourceHashes) || sha256(fs.readFileSync(path.join(dir, 'sources', file))) !== sourceHashes[file],
  )
  const missing = Object.keys(sourceHashes).filter((file) => !found.has(file))
  return [...changed, ...missing].sort()
}
