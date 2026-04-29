import { expect } from 'chai'
import { HDNodeWallet } from 'ethers'
import fs from 'fs'
import JSON5 from 'json5'
import path from 'path'
import { fileURLToPath } from 'url'

/**
 * Deployment config reconciliation
 *
 * Catches drift between the per-network Ignition config files in
 * `packages/horizon/ignition/configs/` and `packages/subgraph-service/ignition/configs/`.
 *
 * Four checks:
 *
 * 1. Cross-package sibling agreement. For each `(prefix, network)` pair where both
 *    horizon and subgraph-service have a config file (e.g. both `migrate.arbitrumOne.json5`),
 *    every overlapping non-empty `$global` field must match. Catches the failure mode where
 *    one package is updated but the sibling drifts.
 *
 * 2. localNetwork all-files `$global` agreement. For localNetwork specifically (one stack,
 *    one governor) every `$global` field meaningfully declared in more than one of the four
 *    `{horizon,subgraph-service}/{migrate,protocol}.localNetwork.json5` files must match
 *    across all of them. Stricter than #1 — catches same-package cross-prefix drift.
 *
 * 3. localNetwork same-package cross-prefix sub-object agreement. For localNetwork, each
 *    package's per-contract config blocks (e.g. `"DisputeManager": { ... }`) must agree
 *    leaf-by-leaf between `migrate` and `protocol`. Catches drift in things like
 *    `eip712Name`/`eip712Version` (which would silently break signature verification) and
 *    `disputePeriod`/`disputeDeposit` parameters. Restricted to localNetwork because for
 *    other networks (notably `default`) migrate and protocol are intentionally different
 *    templates with different parameter values.
 *
 * 4. localNetwork mnemonic-index correctness. Lines like
 *      "governor": "0x70997970…", // index 1
 *    must have an address that derives from the hardhat default mnemonic at the stated
 *    BIP44 index. Catches copy-paste mistakes where someone updates the value but not the
 *    comment, or vice versa.
 */

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const HARDHAT_DEFAULT_MNEMONIC = 'test test test test test test test test test test test junk'
const PACKAGES_DIR = path.resolve(__dirname, '../..')
const PACKAGES = ['horizon', 'subgraph-service'] as const
const CONFIG_FILE_RE = /^(migrate|protocol)\.(.+)\.json5$/

type ConfigPrefix = 'migrate' | 'protocol'

interface ConfigFile {
  package: string
  network: string
  prefix: ConfigPrefix
  filePath: string
  globalFields: Record<string, unknown>
  subObjects: Record<string, Record<string, unknown>>
  rawText: string
}

function discoverConfigs(): ConfigFile[] {
  const out: ConfigFile[] = []
  for (const pkg of PACKAGES) {
    const dir = path.join(PACKAGES_DIR, pkg, 'ignition/configs')
    if (!fs.existsSync(dir)) continue
    for (const file of fs.readdirSync(dir)) {
      const m = CONFIG_FILE_RE.exec(file)
      if (!m) continue
      const filePath = path.join(dir, file)
      const rawText = fs.readFileSync(filePath, 'utf8')
      const parsed = JSON5.parse<Record<string, unknown>>(rawText)
      const globalFields = (parsed.$global ?? {}) as Record<string, unknown>
      const subObjects: Record<string, Record<string, unknown>> = {}
      for (const [k, v] of Object.entries(parsed)) {
        if (k === '$global') continue
        if (typeof v === 'object' && v !== null && !Array.isArray(v)) {
          subObjects[k] = v as Record<string, unknown>
        }
      }
      out.push({
        package: pkg,
        network: m[2],
        prefix: m[1] as ConfigPrefix,
        filePath,
        globalFields,
        subObjects,
        rawText,
      })
    }
  }
  return out
}

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

function isMeaningful(value: unknown): boolean {
  if (value === '' || value === null || value === undefined) return false
  if (typeof value === 'string' && value.toLowerCase() === ZERO_ADDRESS) return false
  return true
}

function deriveHardhatAddress(index: number): string {
  return HDNodeWallet.fromPhrase(HARDHAT_DEFAULT_MNEMONIC, undefined, `m/44'/60'/0'/0/${index}`).address
}

function groupByPrefixAndNetwork(configs: ConfigFile[]): Map<string, ConfigFile[]> {
  const out = new Map<string, ConfigFile[]>()
  for (const c of configs) {
    const key = `${c.prefix}.${c.network}`
    if (!out.has(key)) out.set(key, [])
    out.get(key)!.push(c)
  }
  return out
}

describe('Deployment Config Reconciliation', () => {
  const configs = discoverConfigs()
  const grouped = groupByPrefixAndNetwork(configs)

  describe('Cross-package sibling agreement', () => {
    for (const [key, files] of grouped) {
      if (files.length < 2) continue

      it(`${key}.json5: overlapping $global fields agree across packages`, () => {
        const overlap = new Set<string>()
        for (const field of Object.keys(files[0].globalFields)) {
          if (files.every((f) => isMeaningful(f.globalFields[field]))) overlap.add(field)
        }

        const mismatches: string[] = []
        for (const field of overlap) {
          const distinct = new Set(files.map((f) => JSON.stringify(f.globalFields[field])))
          if (distinct.size > 1) {
            const summary = files.map((f) => `    ${f.package}: ${JSON.stringify(f.globalFields[field])}`).join('\n')
            mismatches.push(`  ${field}:\n${summary}`)
          }
        }

        expect(mismatches, `Cross-package mismatches in ${key}.json5:\n${mismatches.join('\n')}`).to.have.lengthOf(0)
      })
    }
  })

  describe('localNetwork all-files agreement', () => {
    const localNetworkFiles = configs.filter((c) => c.network === 'localNetwork')

    if (localNetworkFiles.length >= 2) {
      it('localNetwork: $global identity fields agree across all (package, prefix) files', () => {
        const allFields = new Set<string>()
        for (const f of localNetworkFiles) {
          for (const [k, v] of Object.entries(f.globalFields)) {
            if (isMeaningful(v)) allFields.add(k)
          }
        }

        const mismatches: string[] = []
        for (const field of allFields) {
          const present = localNetworkFiles.filter((f) => isMeaningful(f.globalFields[field]))
          if (present.length < 2) continue
          const distinct = new Set(present.map((f) => JSON.stringify(f.globalFields[field])))
          if (distinct.size > 1) {
            const summary = present
              .map((f) => `    ${f.package}/${f.prefix}.localNetwork.json5: ${JSON.stringify(f.globalFields[field])}`)
              .join('\n')
            mismatches.push(`  ${field}:\n${summary}`)
          }
        }

        expect(
          mismatches,
          `localNetwork identity-field mismatches across files:\n${mismatches.join('\n')}`,
        ).to.have.lengthOf(0)
      })
    }
  })

  describe('localNetwork same-package cross-prefix sub-object agreement', () => {
    // localNetwork-only: one stack, so per-contract config in protocol and migrate must agree.
    // For other networks (e.g. `default`), migrate and protocol are different templates with
    // intentionally different parameter values.
    for (const pkg of PACKAGES) {
      const migrate = configs.find((c) => c.package === pkg && c.network === 'localNetwork' && c.prefix === 'migrate')
      const protocol = configs.find((c) => c.package === pkg && c.network === 'localNetwork' && c.prefix === 'protocol')
      if (!migrate || !protocol) continue

      it(`${pkg}/localNetwork: per-contract sub-object leaves agree across migrate and protocol`, () => {
        const sharedKeys = Object.keys(migrate.subObjects).filter((k) => k in protocol.subObjects)

        const mismatches: string[] = []
        for (const subKey of sharedKeys) {
          const m = migrate.subObjects[subKey]
          const p = protocol.subObjects[subKey]
          for (const leaf of new Set([...Object.keys(m), ...Object.keys(p)])) {
            if (!(leaf in m) || !(leaf in p)) continue // declared in only one side
            if (JSON.stringify(m[leaf]) !== JSON.stringify(p[leaf])) {
              mismatches.push(
                `  ${subKey}.${leaf}: migrate=${JSON.stringify(m[leaf])} protocol=${JSON.stringify(p[leaf])}`,
              )
            }
          }
        }

        expect(
          mismatches,
          `Sub-object leaf mismatches in ${pkg}/localNetwork:\n${mismatches.join('\n')}`,
        ).to.have.lengthOf(0)
      })
    }
  })

  describe('localNetwork mnemonic-index comments', () => {
    const indexCommentRe = /"(0x[a-fA-F0-9]{40})"\s*,?\s*\/\/\s*index\s+(\d+)/g

    for (const cfg of configs) {
      if (cfg.network !== 'localNetwork') continue

      it(`${cfg.package}/${path.basename(cfg.filePath)}: addresses match // index N comments`, () => {
        const errors: string[] = []
        for (const match of cfg.rawText.matchAll(indexCommentRe)) {
          const [, address, indexStr] = match
          const index = Number.parseInt(indexStr, 10)
          const expected = deriveHardhatAddress(index)
          if (address.toLowerCase() !== expected.toLowerCase()) {
            errors.push(`address ${address} marked "// index ${index}" should be ${expected}`)
          }
        }
        expect(errors, errors.join('\n')).to.have.lengthOf(0)
      })
    }
  })
})
