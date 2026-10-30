import { createHash } from 'node:crypto'
import fs from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'

const require = createRequire(import.meta.url)

export const sha256 = (data) => createHash('sha256').update(data).digest('hex')

export function normalizeRuntime(hex, ranges) {
  const code = hex.toLowerCase().replace(/^0x/, '')
  const metadataLength = parseInt(code.slice(-4), 16)
  const stripped = code.slice(0, code.length - 2 * (metadataLength + 2))
  return ranges.reduce((acc, { start, length }) => {
    const [from, to] = [2 * start, 2 * (start + length)]
    return acc.slice(0, from) + '0'.repeat(to - from) + acc.slice(to)
  }, stripped)
}

export function runtimeRanges(deployedBytecode) {
  const { immutableReferences = {}, linkReferences = {} } = deployedBytecode
  return [
    ...Object.values(immutableReferences).flat(),
    ...Object.values(linkReferences)
      .flatMap((libs) => Object.values(libs))
      .flat(),
  ].map(({ start, length }) => ({ start, length }))
}

export const runtimeHash = (normalized) => sha256(normalized)

const readCompiler = (dir) => JSON.parse(fs.readFileSync(path.join(dir, 'compiler.json'), 'utf8'))

function listSources(dir) {
  const root = path.join(dir, 'sources')
  return fs
    .readdirSync(root, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => path.relative(root, path.join(entry.parentPath, entry.name)).split(path.sep).join('/'))
    .sort()
}

export function compileBundle(dir) {
  const { version, settings, target } = readCompiler(dir)
  const solc = require(`solc-${version.split('+')[0]}`)
  if (!solc.version().startsWith(version)) throw new Error(`expected solc ${version}, loaded ${solc.version()}`)

  const sources = Object.fromEntries(
    listSources(dir).map((file) => [file, { content: fs.readFileSync(path.join(dir, 'sources', file), 'utf8') }]),
  )
  const outputSelection = {
    '*': {
      '*': [
        'evm.deployedBytecode.object',
        'evm.deployedBytecode.immutableReferences',
        'evm.deployedBytecode.linkReferences',
        'storageLayout',
      ],
    },
  }
  const input = { language: 'Solidity', sources, settings: { ...settings, outputSelection } }
  const output = JSON.parse(solc.compile(JSON.stringify(input)))

  const errors = (output.errors ?? []).filter((e) => e.severity === 'error')
  if (errors.length) throw new Error(`${dir}:\n${errors.map((e) => e.formattedMessage).join('\n')}`)

  const contract = output.contracts?.[target.source]?.[target.name]
  if (!contract) throw new Error(`${dir}: no output for ${target.source}:${target.name}`)
  return {
    object: contract.evm.deployedBytecode.object,
    ranges: runtimeRanges(contract.evm.deployedBytecode),
    storageLayout: contract.storageLayout,
  }
}

export function compareAddresses(targets, contracts) {
  return Object.keys(targets)
    .filter((name) => name in contracts)
    .flatMap((name) =>
      ['implementation', 'proxy']
        .filter((key) => String(targets[name][key]).toLowerCase() !== String(contracts[name][key]).toLowerCase())
        .map(
          (key) => `${name}: ${key} is ${targets[name][key]} in targets.json, ${contracts[name][key]} in mainnet.json`,
        ),
    )
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
