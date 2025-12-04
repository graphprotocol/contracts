import fs from 'fs'
import path from 'path'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

export type IssuanceParams = {
  graphToken?: string
  rewardsManager?: string
  // Legacy admin used for GraphProxy upgrades
  graphLegacyProxyAdmin?: string
  // OZ ProxyAdmin for TransparentUpgradeableProxy (issuance components)
  graphIssuanceProxyAdmin?: string
  governor?: string
}

function isAddressLike(v: unknown): v is string {
  return typeof v === 'string' && /^0x[a-fA-F0-9]{40}$/.test(v)
}

function loadJson(file: string): Partial<IssuanceParams> | undefined {
  try {
    if (!fs.existsSync(file)) return undefined
    const raw = fs.readFileSync(file, 'utf8')
    const json = JSON.parse(raw)
    return json as Partial<IssuanceParams>
  } catch {
    return undefined
  }
}

export async function loadParams(hre: HardhatRuntimeEnvironment): Promise<IssuanceParams> {
  const { network } = hre
  const chainId = network.config.chainId
  const configDir = path.resolve(process.cwd(), 'config')

  const candidates = [
    path.join(configDir, `${network.name}.json`),
    chainId ? path.join(configDir, `${chainId}.json`) : '',
    path.join(configDir, `default.json`),
  ].filter(Boolean) as string[]

  const fromFiles: Partial<IssuanceParams> = {}
  for (const file of candidates) {
    const v = loadJson(file)
    if (v) Object.assign(fromFiles, v)
  }

  const fromEnv: Partial<IssuanceParams> = {
    graphToken: process.env.GRAPH_TOKEN,
    rewardsManager: process.env.REWARDS_MANAGER,
    graphLegacyProxyAdmin: process.env.GRAPH_LEGACY_PROXY_ADMIN,
    graphIssuanceProxyAdmin: process.env.GRAPH_ISSUANCE_PROXY_ADMIN,
    governor: process.env.GOVERNOR_ADDRESS,
  }

  const merged: IssuanceParams = {
    ...fromFiles,
    ...fromEnv,
  }

  // Normalize empties
  for (const k of Object.keys(merged) as (keyof IssuanceParams)[]) {
    if (merged[k] && !isAddressLike(merged[k])) delete merged[k]
  }

  return merged
}
