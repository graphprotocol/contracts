/**
 * ABI Codegen Script
 *
 * Generates typed `as const` ABI exports from the contract registry.
 * Reads interface declarations and artifact sources from the registry,
 * resolves them to JSON artifacts, and writes a generated TypeScript file.
 *
 * Usage: tsx scripts/generate-abis.ts
 */

import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { toFunctionSelector } from 'viem'

import { CONTRACT_REGISTRY, type ContractMetadata, type InterfaceAbiConfig } from '../lib/contract-registry.js'

const require = createRequire(import.meta.url)
const __dirname = dirname(fileURLToPath(import.meta.url))
const OUTPUT_DIR = join(__dirname, '..', 'lib', 'generated')
const OUTPUT_FILE = join(OUTPUT_DIR, 'abis.ts')

// ---------------------------------------------------------------------------
// Utility ABIs — not tied to any registry entry
// ---------------------------------------------------------------------------

const UTILITY_ABIS: Array<{ name: string; artifactPath: string }> = [
  {
    name: 'IERC165_ABI',
    artifactPath: '@graphprotocol/interfaces/artifacts/@openzeppelin/contracts/introspection/IERC165.sol/IERC165.json',
  },
  {
    name: 'ISSUANCE_TARGET_ABI',
    artifactPath:
      '@graphprotocol/interfaces/artifacts/contracts/issuance/allocate/IIssuanceTarget.sol/IIssuanceTarget.json',
  },
  {
    name: 'OZ_PROXY_ADMIN_ABI',
    artifactPath:
      '@graphprotocol/horizon/artifacts/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol/ProxyAdmin.json',
  },
]

// Alias re-exports (source export name → alias export name)
const ABI_ALIASES: Array<{ source: string; alias: string }> = [
  { source: 'ISSUANCE_ALLOCATOR_ABI', alias: 'SET_TARGET_ALLOCATION_ABI' },
  { source: 'DIRECT_ALLOCATION_ABI', alias: 'INITIALIZE_GOVERNOR_ABI' },
]

// Interface IDs to extract (export name → interface name used in ABI_SOURCES or registry)
// Derived from registry interfaces + utility ABIs
const INTERFACE_IDS: Array<{ name: string; abiExportName: string }> = [
  { name: 'IERC165_INTERFACE_ID', abiExportName: 'IERC165_ABI' },
  { name: 'IISSUANCE_TARGET_INTERFACE_ID', abiExportName: 'ISSUANCE_TARGET_ABI' },
  { name: 'IREWARDS_MANAGER_INTERFACE_ID', abiExportName: 'REWARDS_MANAGER_ABI' },
]

// ---------------------------------------------------------------------------
// Interface artifact discovery
// ---------------------------------------------------------------------------

/**
 * Build an index of interface name → artifact path by scanning the
 * @graphprotocol/interfaces artifacts directory.
 */
function buildInterfaceIndex(): Map<string, string> {
  const index = new Map<string, string>()

  // Resolve the interfaces package artifacts root
  // Use a known artifact to locate the package, then walk up
  const knownArtifact =
    require.resolve('@graphprotocol/interfaces/artifacts/contracts/contracts/rewards/IRewardsManager.sol/IRewardsManager.json')
  // Walk up to find the 'artifacts' directory
  let artifactsRoot = dirname(knownArtifact)
  while (!artifactsRoot.endsWith('/artifacts') && artifactsRoot !== '/') {
    artifactsRoot = dirname(artifactsRoot)
  }

  // Recursively scan for JSON files
  function scan(dir: string): void {
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry)
      if (entry === 'build-info') continue
      if (statSync(full).isDirectory()) {
        scan(full)
      } else if (entry.endsWith('.json') && !entry.endsWith('.dbg.json')) {
        // Extract interface name from filename (e.g. IRewardsManager.json → IRewardsManager)
        const name = entry.replace('.json', '')
        // Store as package-relative path for require.resolve
        const relativePath = full.slice(full.indexOf('/artifacts/') + 1)
        index.set(name, `@graphprotocol/interfaces/${relativePath}`)
      }
    }
  }

  scan(artifactsRoot)
  return index
}

// ---------------------------------------------------------------------------
// Artifact loading
// ---------------------------------------------------------------------------

type AbiEntry = Record<string, unknown>

function loadAbiFromArtifact(artifactPath: string): AbiEntry[] {
  const resolved = require.resolve(artifactPath)
  const artifact = JSON.parse(readFileSync(resolved, 'utf-8'))
  return artifact.abi
}

/**
 * Resolve artifact path for a generateAbi entry based on its ArtifactSource.
 */
function resolveContractArtifactPath(artifact: { type: string; path?: string; name?: string }): string {
  switch (artifact.type) {
    case 'contracts':
      return `@graphprotocol/contracts/artifacts/contracts/${artifact.path}/${artifact.name}.sol/${artifact.name}.json`
    case 'subgraph-service': {
      const baseName = (artifact.name ?? '').includes('/') ? (artifact.name ?? '').split('/').pop()! : artifact.name
      return `@graphprotocol/subgraph-service/artifacts/contracts/${artifact.name}.sol/${baseName}.json`
    }
    case 'horizon':
      return `@graphprotocol/horizon/artifacts/${artifact.path}.json`
    case 'issuance':
      return `@graphprotocol/issuance/artifacts/${artifact.path}.json`
    case 'openzeppelin':
      return `@openzeppelin/contracts/build/contracts/${artifact.name}.json`
    default:
      throw new Error(`Unknown artifact type: ${artifact.type}`)
  }
}

// ---------------------------------------------------------------------------
// Interface ID calculation
// ---------------------------------------------------------------------------

/**
 * Calculate ERC-165 interface ID from an ABI.
 * The interface ID is XOR of all function selectors.
 */
function calculateInterfaceId(abi: AbiEntry[]): string {
  const functions = abi.filter((entry) => entry.type === 'function')
  if (functions.length === 0) return '0x00000000'

  let id = BigInt(0)
  for (const fn of functions) {
    const inputs = (fn.inputs as Array<{ type: string }>) ?? []
    const sig = `${fn.name}(${inputs.map((i) => i.type).join(',')})`
    const selector = toFunctionSelector(sig)
    id ^= BigInt(selector)
  }

  return '0x' + id.toString(16).padStart(8, '0')
}

// ---------------------------------------------------------------------------
// Code generation
// ---------------------------------------------------------------------------

function formatAbiEntry(entry: AbiEntry, indent: string): string {
  return `${indent}${JSON.stringify(entry)}`
}

function generateAbiExport(name: string, abi: AbiEntry[]): string {
  const entries = abi.map((entry) => formatAbiEntry(entry, '  ')).join(',\n')
  return `export const ${name} = [\n${entries},\n] as const\n`
}

function main(): void {
  const verbose = process.argv.includes('--verbose')

  const interfaceIndex = buildInterfaceIndex()
  const abiMap = new Map<string, AbiEntry[]>()
  const lines: string[] = [
    '/**',
    ' * Auto-generated typed ABI exports',
    ' *',
    ' * DO NOT EDIT — regenerate with: pnpm generate:abis',
    ' */',
    '',
  ]

  // 1. Walk registry for interface ABIs
  for (const [bookName, book] of Object.entries(CONTRACT_REGISTRY)) {
    for (const [contractName, rawMeta] of Object.entries(book)) {
      const meta = rawMeta as ContractMetadata
      // Interface ABIs
      if (meta.interfaces) {
        for (const iface of meta.interfaces as readonly InterfaceAbiConfig[]) {
          const artifactPath = interfaceIndex.get(iface.interface)
          if (!artifactPath) {
            throw new Error(
              `Interface "${iface.interface}" not found in @graphprotocol/interfaces artifacts ` +
                `(referenced by ${bookName}.${contractName})`,
            )
          }
          const abi = loadAbiFromArtifact(artifactPath)
          abiMap.set(iface.name, abi)
          if (verbose) console.log(`  ${iface.name} ← ${iface.interface} (${abi.length} entries)`)
        }
      }

      // Full contract ABI
      if (meta.generateAbi && meta.artifact) {
        const exportName = meta.generateAbi as string
        const artifactPath = resolveContractArtifactPath(
          meta.artifact as { type: string; path?: string; name?: string },
        )
        const abi = loadAbiFromArtifact(artifactPath)
        abiMap.set(exportName, abi)
        if (verbose) console.log(`  ${exportName} ← ${contractName} (${abi.length} entries)`)
      }
    }
  }

  // 2. Utility ABIs
  for (const util of UTILITY_ABIS) {
    const abi = loadAbiFromArtifact(util.artifactPath)
    abiMap.set(util.name, abi)
    if (verbose) console.log(`  ${util.name} ← utility (${abi.length} entries)`)
  }

  // 3. Generate ABI exports
  for (const [name, abi] of abiMap) {
    lines.push(generateAbiExport(name, abi))
  }

  // 4. Alias re-exports
  for (const { source, alias } of ABI_ALIASES) {
    if (!abiMap.has(source)) {
      throw new Error(`Alias source "${source}" not found in generated ABIs`)
    }
    lines.push(`export { ${source} as ${alias} }\n`)
    if (verbose) console.log(`  ${alias} → ${source}`)
  }

  // 5. Interface IDs
  lines.push('// Interface IDs (computed from ABI function selectors)')
  for (const { name, abiExportName } of INTERFACE_IDS) {
    const abi = abiMap.get(abiExportName)
    if (!abi) {
      throw new Error(`ABI "${abiExportName}" not found for interface ID "${name}"`)
    }
    const id = calculateInterfaceId(abi)
    lines.push(`export const ${name} = '${id}' as const`)
    if (verbose) console.log(`  ${name} = ${id}`)
  }
  lines.push('')

  // Write output
  if (!existsSync(OUTPUT_DIR)) {
    mkdirSync(OUTPUT_DIR, { recursive: true })
  }
  writeFileSync(OUTPUT_FILE, lines.join('\n'))

  console.log(
    `Generated ${abiMap.size} ABIs, ${ABI_ALIASES.length} aliases, ${INTERFACE_IDS.length} interface IDs → lib/generated/abis.ts`,
  )
}

main()
