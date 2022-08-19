import { L1ToL2MessageGasEstimator } from '@arbitrum/sdk'
import { BigNumber, providers } from 'ethers'
import { parseEther } from 'ethers/lib/utils'

import { logger } from './logging'

export const l1ToL2ChainIdMap = {
  '1': '42161',
  '4': '421611',
  '5': '421613',
  '1337': '412346',
}

export const l2ChainIds = Object.values(l1ToL2ChainIdMap).map(Number)
export const l2ToL1ChainIdMap = Object.fromEntries(
  Object.entries(l1ToL2ChainIdMap).map(([k, v]) => [v, k]),
)

export const chainIdIsL2 = (chainId: number | string): boolean => {
  return l2ChainIds.includes(Number(chainId))
}

interface L2GasParams {
  maxGas: BigNumber
  gasPriceBid: BigNumber
  maxSubmissionCost: BigNumber
}

export const estimateRetryableTxGas = async (
  l1Provider: providers.Provider,
  l2Provider: providers.Provider,
  gatewayAddress: string,
  l2Dest: string,
  depositCalldata: string,
  opts: L2GasParams,
): Promise<L2GasParams> => {
  const autoEstimate = opts && (!opts.maxGas || !opts.gasPriceBid || !opts.maxSubmissionCost)
  if (!autoEstimate) {
    return opts
  }

  // Comment from Offchain Labs' implementation:
  // we add a 0.05 ether "deposit" buffer to pay for execution in the gas estimation
  logger.info('Estimating retryable ticket gas:')
  const baseFee = (await l1Provider.getBlock('latest')).baseFeePerGas
  const gasEstimator = new L1ToL2MessageGasEstimator(l2Provider)
  const gasParams = await gasEstimator.estimateAll(
    gatewayAddress,
    l2Dest,
    depositCalldata,
    parseEther('0'),
    baseFee as BigNumber,
    gatewayAddress,
    gatewayAddress,
    l1Provider,
  )
  // override fixed values
  return {
    maxGas: opts.maxGas ?? gasParams.gasLimit,
    gasPriceBid: opts.gasPriceBid ?? gasParams.maxFeePerGas,
    maxSubmissionCost: opts.maxSubmissionCost ?? gasParams.maxSubmissionFee,
  }
}
