import { execSync } from 'child_process'
import fs from 'fs'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import https from 'https'
import path from 'path'

import { AddressBookEntry, AddressBookJson } from '../deployments/address-book'

export interface TenderlyConfig {
  username: string
  networks: {
    [chainId: number]: {
      project: string
    }
  }
  externalArtifacts?: {
    source: string
    buildInfo: string
  }
  verifyList?: string[]
  excludeList?: string[]
  tag?: string
}

export interface ContractInfo {
  name: string
  address: string
  verifyAddress: string
  isLocal: boolean
  shouldVerify: boolean
  artifactPath?: string
  sourcePath?: string
}

export interface BuildInfo {
  solcVersion: string
  input: {
    settings: {
      optimizer: {
        enabled: boolean
        runs: number
      }
      evmVersion?: string
    }
    sources: {
      [sourceName: string]: {
        content: string
      }
    }
  }
}

export interface TenderlySourceFile {
  name: string
  code: string
}

// Re-export for convenience
export type { AddressBookEntry, AddressBookJson }

export interface TenderlyPlugin {
  verify(contract: { name: string; address: string }): Promise<void>
  verifyMultiCompilerAPI(request: {
    contracts: Array<{
      contractToVerify: string
      sources: Record<string, TenderlySourceFile>
      compiler: {
        version: string
        settings: Record<string, unknown>
      }
      networks: Record<string, { address: string }>
    }>
  }): Promise<void>
}

export function loadTenderlyConfig(packageDir: string): TenderlyConfig {
  const configPath = path.join(packageDir, 'tenderly.config.json')

  if (!fs.existsSync(configPath)) {
    throw new Error(`Tenderly config not found at ${configPath}`)
  }

  return JSON.parse(fs.readFileSync(configPath, 'utf8'))
}

export function copyExternalArtifacts(packageDir: string, config: TenderlyConfig): void {
  if (!config.externalArtifacts) {
    return
  }

  const destDir = path.join(packageDir, '.tenderly-artifacts')
  const sourceDir = path.resolve(packageDir, config.externalArtifacts.source)

  console.log(`Copying external artifacts from ${sourceDir}...`)

  if (!fs.existsSync(destDir)) {
    fs.mkdirSync(destDir, { recursive: true })
  }

  const sourcePath = path.join(sourceDir, 'contracts')
  const destPath = path.join(destDir, 'contracts')

  if (fs.existsSync(sourcePath)) {
    execSync(`rsync -a "${sourcePath}/" "${destPath}/"`, { stdio: 'inherit' })
  }

  const buildInfoSource = path.resolve(packageDir, config.externalArtifacts.buildInfo)
  const buildInfoDest = path.join(destDir, 'build-info')

  if (fs.existsSync(buildInfoSource)) {
    execSync(`rsync -a "${buildInfoSource}/" "${buildInfoDest}/"`, { stdio: 'inherit' })
  }

  console.log(`✓ External artifacts copied to ${destDir}`)
}

export function findArtifact(contractName: string, searchDirs: string[]): string | null {
  for (const searchDir of searchDirs) {
    if (!fs.existsSync(searchDir)) {
      continue
    }

    const found = findFileRecursive(searchDir, contractName)

    if (found) {
      return found
    }
  }

  return null
}

function findFileRecursive(dir: string, contractName: string): string | null {
  const entries = fs.readdirSync(dir, { withFileTypes: true })

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name)

    if (entry.isDirectory()) {
      if (entry.name === `${contractName}.sol`) {
        const jsonPath = path.join(fullPath, `${contractName}.json`)
        if (fs.existsSync(jsonPath)) {
          return jsonPath
        }
      }

      const found = findFileRecursive(fullPath, contractName)
      if (found) {
        return found
      }
    }
  }

  return null
}

function isLocalContract(artifactPath: string, packageDir: string): boolean {
  try {
    const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'))

    if (!artifact.deployedBytecode || artifact.deployedBytecode === '0x') {
      return false
    }

    const sourceName = artifact.sourceName || ''
    if (sourceName.includes('/interfaces/') || sourceName.startsWith('I')) {
      return false
    }

    if (sourceName.startsWith('@graphprotocol/')) {
      return false
    }

    if (sourceName.startsWith('contracts/')) {
      const sourceFile = path.join(packageDir, sourceName)
      if (fs.existsSync(sourceFile)) {
        return true
      }
    }

    return false
  } catch {
    return false
  }
}

export function classifyContracts(
  packageDir: string,
  deployments: Record<string, AddressBookEntry>,
  verifyList?: string[],
  excludeList?: string[],
): ContractInfo[] {
  const contracts: ContractInfo[] = []
  const localArtifactsDir = path.join(packageDir, 'build', 'contracts', 'contracts')
  const externalArtifactsDir = path.join(packageDir, '.tenderly-artifacts', 'contracts')

  for (const [contractName, contractData] of Object.entries(deployments)) {
    if (typeof contractData !== 'object' || !contractData) {
      continue
    }

    if (excludeList?.includes(contractName)) {
      continue
    }

    const address = contractData.address
    const verifyAddress = contractData.implementation || contractData.address

    if (!address) {
      console.warn(`⚠ Skipping ${contractName}: no address found`)
      continue
    }

    const shouldVerify = verifyList ? verifyList.includes(contractName) : false

    const localArtifact = findArtifact(contractName, [localArtifactsDir])

    if (localArtifact && isLocalContract(localArtifact, packageDir)) {
      contracts.push({
        name: contractName,
        address,
        verifyAddress,
        isLocal: true,
        shouldVerify,
        artifactPath: localArtifact,
      })
    } else {
      const externalArtifact = findArtifact(contractName, [externalArtifactsDir])

      if (externalArtifact) {
        const artifact = JSON.parse(fs.readFileSync(externalArtifact, 'utf8'))
        contracts.push({
          name: contractName,
          address,
          verifyAddress,
          isLocal: false,
          shouldVerify,
          artifactPath: externalArtifact,
          sourcePath: artifact.sourceName,
        })
      } else if (shouldVerify) {
        console.warn(`⚠ Skipping ${contractName}: artifact not found (required for verification)`)
      } else {
        contracts.push({
          name: contractName,
          address,
          verifyAddress,
          isLocal: false,
          shouldVerify: false,
        })
      }
    }
  }

  return contracts
}

export async function addContractToTenderly(
  address: string,
  networkId: number,
  displayName: string,
  config: TenderlyConfig,
  accessToken: string,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const networkConfig = config.networks[networkId]
    if (!networkConfig) {
      reject(new Error(`No Tenderly project configured for network ${networkId}`))
      return
    }

    const data = JSON.stringify({
      address: address,
      network_id: String(networkId),
      display_name: displayName,
    })

    const options = {
      hostname: 'api.tenderly.co',
      port: 443,
      path: `/api/v1/account/${config.username}/project/${networkConfig.project}/address`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length,
        'X-Access-Key': accessToken,
      },
    }

    const req = https.request(options, (res) => {
      let responseData = ''

      res.on('data', (chunk) => {
        responseData += chunk
      })

      res.on('end', () => {
        if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
          resolve()
        } else if (res.statusCode === 409) {
          resolve()
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${responseData}`))
        }
      })
    })

    req.on('error', reject)
    req.write(data)
    req.end()
  })
}

export async function tagContractsOnTenderly(
  addresses: string[],
  networkId: number,
  tag: string,
  config: TenderlyConfig,
  accessToken: string,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const networkConfig = config.networks[networkId]
    if (!networkConfig) {
      reject(new Error(`No Tenderly project configured for network ${networkId}`))
      return
    }

    const data = JSON.stringify({
      contract_ids: addresses.map((addr) => `eth:${networkId}:${addr.toLowerCase()}`),
      tag: tag,
    })

    const options = {
      hostname: 'api.tenderly.co',
      port: 443,
      path: `/api/v1/account/${config.username}/project/${networkConfig.project}/tag`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length,
        'X-Access-Key': accessToken,
      },
    }

    const req = https.request(options, (res) => {
      let responseData = ''

      res.on('data', (chunk) => {
        responseData += chunk
      })

      res.on('end', () => {
        if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
          resolve()
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${responseData}`))
        }
      })
    })

    req.on('error', reject)
    req.write(data)
    req.end()
  })
}

export async function verifyLocalContract(
  tenderly: TenderlyPlugin,
  contractName: string,
  verifyAddress: string,
): Promise<void> {
  await tenderly.verify({
    name: contractName,
    address: verifyAddress,
  })
}

export async function verifyExternalContract(
  tenderly: TenderlyPlugin,
  contract: ContractInfo,
  networkId: number,
  packageDir: string,
): Promise<void> {
  if (!contract.artifactPath || !contract.sourcePath) {
    throw new Error(`Missing artifact or source path for ${contract.name}`)
  }

  const buildInfoFile = findBuildInfoForContract(contract.sourcePath, packageDir)
  if (!buildInfoFile) {
    throw new Error(`Build info not found for ${contract.name}`)
  }

  const buildInfo: BuildInfo = JSON.parse(fs.readFileSync(buildInfoFile, 'utf8'))

  const sources: Record<string, TenderlySourceFile> = {}
  for (const [sourceName, sourceData] of Object.entries(buildInfo.input.sources)) {
    sources[sourceName] = {
      name: path.basename(sourceName, '.sol'),
      code: sourceData.content,
    }
  }

  const compilerSettings = {
    ...buildInfo.input.settings,
    evmVersion: buildInfo.input.settings.evmVersion || 'istanbul',
  }

  await tenderly.verifyMultiCompilerAPI({
    contracts: [
      {
        contractToVerify: `${contract.sourcePath}:${contract.name}`,
        sources: sources,
        compiler: {
          version: buildInfo.solcVersion,
          settings: compilerSettings,
        },
        networks: {
          [networkId]: {
            address: contract.verifyAddress,
          },
        },
      },
    ],
  })
}

function findBuildInfoForContract(sourcePath: string, packageDir: string): string | null {
  const buildInfoDir = path.join(packageDir, '.tenderly-artifacts', 'build-info')

  if (!fs.existsSync(buildInfoDir)) {
    return null
  }

  const buildInfoFiles = fs.readdirSync(buildInfoDir).filter((f) => f.endsWith('.json'))

  for (const file of buildInfoFiles) {
    try {
      const buildInfoPath = path.join(buildInfoDir, file)
      const buildInfo = JSON.parse(fs.readFileSync(buildInfoPath, 'utf8'))

      if (buildInfo.input?.sources && sourcePath in buildInfo.input.sources) {
        return buildInfoPath
      }
    } catch {
      continue
    }
  }

  return null
}

export async function runTenderlyUpload(
  hre: HardhatRuntimeEnvironment,
  tenderly: TenderlyPlugin,
  packageDir: string,
  addresses: AddressBookJson,
  accessToken: string,
  taskArgs: { noVerify: boolean; skipAdd: boolean },
): Promise<void> {
  const { network } = hre

  const chainId = network.config.chainId
  if (!chainId) {
    throw new Error('Network chain ID not found')
  }

  console.log(`\nUploading contracts to Tenderly`)
  console.log(`Network: ${network.name} (${chainId})`)

  const tenderlyConfig = loadTenderlyConfig(packageDir)
  const networkConfig = tenderlyConfig.networks[chainId]

  if (!networkConfig) {
    throw new Error(`No Tenderly project configured for network ${chainId}`)
  }

  console.log(`Tenderly project: ${tenderlyConfig.username}/${networkConfig.project}\n`)

  // Copy external artifacts if configured
  if (tenderlyConfig.externalArtifacts) {
    copyExternalArtifacts(packageDir, tenderlyConfig)
    console.log()
  }

  const deployments = addresses[chainId]
  if (!deployments) {
    throw new Error(`No deployments found for network ${chainId}`)
  }

  const contracts = classifyContracts(packageDir, deployments, tenderlyConfig.verifyList, tenderlyConfig.excludeList)

  console.log(`\nFound ${contracts.length} contracts:`)
  const localCount = contracts.filter((c) => c.isLocal).length
  const externalCount = contracts.filter((c) => !c.isLocal).length
  const verifyCount = contracts.filter((c) => c.shouldVerify).length
  console.log(`  ${localCount} local contracts`)
  console.log(`  ${externalCount} external contracts`)
  console.log(`  ${verifyCount} to verify (in verifyList)\n`)

  // Step 1: Add all contracts to Tenderly project
  if (!taskArgs.skipAdd) {
    console.log(`\n${'='.repeat(60)}`)
    console.log(`Step 1: Adding contracts to Tenderly project`)
    console.log(`${'='.repeat(60)}\n`)

    let addedCount = 0
    let addFailedCount = 0

    for (const contract of contracts) {
      try {
        console.log(`Adding ${contract.name} (${contract.address})...`)
        await addContractToTenderly(contract.address, chainId, contract.name, tenderlyConfig, accessToken)
        console.log(`  ✓ Added\n`)
        addedCount++

        await new Promise((resolve) => setTimeout(resolve, 500))
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error)
        console.error(`  ✗ Failed: ${message}\n`)
        addFailedCount++
      }
    }

    console.log(`Summary: ${addedCount} added, ${addFailedCount} failed\n`)

    // Tag contracts if configured
    if (tenderlyConfig.tag) {
      console.log(`Tagging contracts with "${tenderlyConfig.tag}"...`)
      try {
        await tagContractsOnTenderly(
          contracts.map((c) => c.address),
          chainId,
          tenderlyConfig.tag,
          tenderlyConfig,
          accessToken,
        )
        console.log(`  ✓ Tagged ${contracts.length} contracts\n`)
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error)
        console.error(`  ✗ Failed to tag: ${message}\n`)
      }
    }
  } else {
    console.log(`\nSkipping add step (--skip-add flag set)\n`)
  }

  // Step 2: Verify contracts (if not skipped)
  if (!taskArgs.noVerify) {
    console.log(`\n${'='.repeat(60)}`)
    console.log(`Step 2: Verifying contracts`)
    console.log(`${'='.repeat(60)}\n`)

    const contractsToVerify = contracts.filter((c) => c.shouldVerify)
    const contractsToSkip = contracts.filter((c) => !c.shouldVerify)

    console.log(`Verifying ${contractsToVerify.length} of ${contracts.length} contracts (allowlist)`)
    if (contractsToSkip.length > 0) {
      console.log(`Skipping verification for: ${contractsToSkip.map((c) => c.name).join(', ')}\n`)
    }

    let verifiedCount = 0
    let verifyFailedCount = 0

    for (const contract of contractsToVerify) {
      try {
        console.log(`Verifying ${contract.name}...`)
        console.log(`  Type: ${contract.isLocal ? 'local' : 'external'}`)

        if (contract.isLocal) {
          await verifyLocalContract(tenderly, contract.name, contract.verifyAddress)
        } else {
          await verifyExternalContract(tenderly, contract, chainId, packageDir)
        }

        console.log(`  ✓ Verified\n`)
        verifiedCount++

        await new Promise((resolve) => setTimeout(resolve, 1000))
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error)
        console.error(`  ✗ Failed: ${message}\n`)
        verifyFailedCount++
      }
    }

    console.log(`Summary: ${verifiedCount} verified, ${verifyFailedCount} failed\n`)
  } else {
    console.log(`\nSkipping verification (--no-verify flag set)\n`)
  }

  console.log(`\n${'='.repeat(60)}`)
  console.log(`Upload complete!`)
  console.log(`${'='.repeat(60)}`)
  console.log(
    `\nView contracts: https://dashboard.tenderly.co/${tenderlyConfig.username}/${networkConfig.project}/contracts\n`,
  )
}
