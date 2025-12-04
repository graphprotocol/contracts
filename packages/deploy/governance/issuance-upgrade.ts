import { connectGraphIssuance } from '@graphprotocol/toolshed/deployments'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import path from 'path'

import { TxBuilder } from './tx-builder'

export interface IssuanceContractUpgradeParams {
  contractName: 'IssuanceAllocator' | 'RewardsEligibilityOracle' | 'PilotAllocation'
  newImplementation: string
  graphIssuanceProxyAdminAddress?: string
  callData?: string // Optional calldata for upgradeAndCall (defaults to '0x')
}

export interface IssuanceContractUpgradeOptions {
  txBuilderTemplate?: string
  outputDir?: string
}

export interface IssuanceContractUpgradeResult {
  chainId: number
  outputFile: string
}

/**
 * Build Safe TX batch for upgrading issuance contracts via GraphIssuanceProxyAdmin
 *
 * This generates a governance transaction to upgrade an issuance contract (IA, REO, or PA)
 * to a new implementation using OpenZeppelin's ProxyAdmin.upgradeAndCall().
 *
 * @param hre Hardhat Runtime Environment
 * @param params Upgrade parameters (contract name, new implementation address, optional calldata)
 * @param options Output options (template path, output directory)
 * @returns Result with chainId and output file path
 */
export async function buildIssuanceContractUpgradeTxs(
  hre: HardhatRuntimeEnvironment,
  params: IssuanceContractUpgradeParams,
  options: IssuanceContractUpgradeOptions = {},
): Promise<IssuanceContractUpgradeResult> {
  const chainId = Number(hre.network.config.chainId ?? (await hre.ethers.provider.getNetwork()).chainId)
  const provider = hre.ethers.provider

  const issuanceContracts = connectGraphIssuance(chainId, provider)

  if (!issuanceContracts.GraphIssuanceProxyAdmin) {
    throw new Error('GraphIssuanceProxyAdmin not found in Issuance address book')
  }

  // Get the proxy address based on contract name
  let proxyAddress: string
  switch (params.contractName) {
    case 'IssuanceAllocator':
      if (!issuanceContracts.IssuanceAllocator) {
        throw new Error('IssuanceAllocator not found in Issuance address book')
      }
      proxyAddress = issuanceContracts.IssuanceAllocator.target.toString()
      break
    case 'RewardsEligibilityOracle':
      if (!issuanceContracts.RewardsEligibilityOracle) {
        throw new Error('RewardsEligibilityOracle not found in Issuance address book')
      }
      proxyAddress = issuanceContracts.RewardsEligibilityOracle.target.toString()
      break
    case 'PilotAllocation':
      if (!issuanceContracts.PilotAllocation) {
        throw new Error('PilotAllocation not found in Issuance address book')
      }
      proxyAddress = issuanceContracts.PilotAllocation.target.toString()
      break
    default:
      throw new Error(`Unknown contract name: ${params.contractName}`)
  }

  const graphIssuanceProxyAdminAddress =
    params.graphIssuanceProxyAdminAddress ?? issuanceContracts.GraphIssuanceProxyAdmin.target.toString()
  const newImplementation = params.newImplementation
  const callData = params.callData ?? '0x' // Default to no call data

  const templatePath = options.txBuilderTemplate
    ? path.isAbsolute(options.txBuilderTemplate)
      ? options.txBuilderTemplate
      : path.resolve(process.cwd(), options.txBuilderTemplate)
    : path.resolve(__dirname, 'tx-builder-template.json')

  const outputDir = options.outputDir
    ? path.isAbsolute(options.outputDir)
      ? options.outputDir
      : path.resolve(process.cwd(), options.outputDir)
    : process.cwd()

  const builder = new TxBuilder(chainId, { template: templatePath, outputDir })

  // OpenZeppelin ProxyAdmin.upgradeAndCall(proxy, implementation, data)
  const upgradeAndCallTx = await issuanceContracts.GraphIssuanceProxyAdmin.populateTransaction.upgradeAndCall(
    proxyAddress,
    newImplementation,
    callData,
  )

  builder.addTx({
    to: graphIssuanceProxyAdminAddress,
    value: '0',
    data: upgradeAndCallTx.data ?? '0x',
  })

  const outputFile = builder.saveToFile()

  return {
    chainId: Number(chainId),
    outputFile,
  }
}
