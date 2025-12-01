import { connectGraphHorizon, connectGraphIssuance } from '@graphprotocol/toolshed/deployments'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import path from 'path'

import { TxBuilder } from './tx-builder'

export interface RewardsEligibilityUpgradeParams {
  rewardsManagerImplementation: string
  rewardsManagerAddress?: string
  graphProxyAdmin?: string
  rewardsEligibilityOracleAddress?: string
}

export interface RewardsEligibilityUpgradeOptions {
  txBuilderTemplate?: string
  outputDir?: string
}

export interface RewardsEligibilityUpgradeResult {
  chainId: number
  outputFile: string
}

export async function buildRewardsEligibilityUpgradeTxs(
  hre: HardhatRuntimeEnvironment,
  params: RewardsEligibilityUpgradeParams,
  options: RewardsEligibilityUpgradeOptions = {},
): Promise<RewardsEligibilityUpgradeResult> {
  const chainId = Number(hre.network.config.chainId ?? (await hre.ethers.provider.getNetwork()).chainId)
  const provider = hre.ethers.provider

  const horizonContracts = connectGraphHorizon(chainId, provider)
  const issuanceContracts = connectGraphIssuance(chainId, provider)

  if (!horizonContracts.GraphProxyAdmin || !horizonContracts.RewardsManager) {
    throw new Error('GraphProxyAdmin or RewardsManager not found in Horizon address book')
  }

  if (!issuanceContracts.IssuanceAllocator || !issuanceContracts.RewardsEligibilityOracle) {
    throw new Error('IssuanceAllocator or RewardsEligibilityOracle not found in Issuance address book')
  }

  const graphProxyAdminAddress = params.graphProxyAdmin ?? horizonContracts.GraphProxyAdmin.target.toString()
  const rewardsManagerProxy = params.rewardsManagerAddress ?? horizonContracts.RewardsManager.target.toString()
  const rewardsManagerImplementation = params.rewardsManagerImplementation
  const issuanceAllocatorAddress = issuanceContracts.IssuanceAllocator.target.toString()
  const rewardsEligibilityOracleAddress =
    params.rewardsEligibilityOracleAddress ?? issuanceContracts.RewardsEligibilityOracle.target.toString()

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

  const upgradeTx = await horizonContracts.GraphProxyAdmin.populateTransaction.upgrade(
    rewardsManagerProxy,
    rewardsManagerImplementation,
  )

  const acceptTx = await horizonContracts.GraphProxyAdmin.populateTransaction.acceptProxy(
    rewardsManagerImplementation,
    rewardsManagerProxy,
  )

  const setAllocatorTx = await horizonContracts.RewardsManager.populateTransaction.setIssuanceAllocator(
    issuanceAllocatorAddress,
  )

  const setOracleTx = await horizonContracts.RewardsManager.populateTransaction.setRewardsEligibilityOracle(
    rewardsEligibilityOracleAddress,
  )

  builder.addTx({
    to: graphProxyAdminAddress,
    value: '0',
    data: upgradeTx.data ?? '0x',
  })

  builder.addTx({
    to: graphProxyAdminAddress,
    value: '0',
    data: acceptTx.data ?? '0x',
  })

  builder.addTx({
    to: rewardsManagerProxy,
    value: '0',
    data: setAllocatorTx.data ?? '0x',
  })

  builder.addTx({
    to: rewardsManagerProxy,
    value: '0',
    data: setOracleTx.data ?? '0x',
  })

  const outputFile = builder.saveToFile()

  return {
    chainId: Number(chainId),
    outputFile,
  }
}

