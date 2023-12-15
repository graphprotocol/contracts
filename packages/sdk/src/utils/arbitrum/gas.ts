import { L1ToL2MessageGasEstimator } from '@arbitrum/sdk'
import { parseEther } from 'ethers/lib/utils'

import type { L1ToL2MessageNoGasParams } from '@arbitrum/sdk/dist/lib/message/L1ToL2MessageCreator'
import type { GasOverrides } from '@arbitrum/sdk/dist/lib/message/L1ToL2MessageGasEstimator'
import type { BigNumber, providers } from 'ethers'

export interface L2GasParams {
  maxGas: BigNumber
  gasPriceBid: BigNumber
  maxSubmissionCost: BigNumber
}

/**
 * Estimate gas parameters for a retryable ticket creation
 *
 * @remark Uses Arbitrum's SDK to estimate the parameters
 *
 * @param l1Provider Provider for the L1 network (ethereum)
 * @param l2Provider Provider for the L2 network (arbitrum)
 * @param gatewayAddress Address where the tickets will be sent from in L1
 * @param l2Dest Address of the destination in L2
 * @param depositCalldata Calldata to be sent to L2
 * @param opts Gas parameters to be used if not auto-estimated
 * @returns estimated gas parameters
 */
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

  console.info('Estimating retryable ticket gas:')
  const baseFee = (await l1Provider.getBlock('latest')).baseFeePerGas
  const gasEstimator = new L1ToL2MessageGasEstimator(l2Provider)
  const retryableEstimateData: L1ToL2MessageNoGasParams = {
    from: gatewayAddress,
    to: l2Dest,
    data: depositCalldata,
    l2CallValue: parseEther('0'),
    excessFeeRefundAddress: gatewayAddress,
    callValueRefundAddress: gatewayAddress,
  }

  const estimateOpts: GasOverrides = {}
  if (opts.maxGas) estimateOpts.gasLimit = { base: opts.maxGas }
  if (opts.maxSubmissionCost) estimateOpts.maxSubmissionFee = { base: opts.maxSubmissionCost }
  if (opts.gasPriceBid) estimateOpts.maxFeePerGas = { base: opts.gasPriceBid }

  const gasParams = await gasEstimator.estimateAll(
    retryableEstimateData,
    baseFee as BigNumber,
    l1Provider,
    estimateOpts,
  )

  return {
    maxGas: opts.maxGas ?? gasParams.gasLimit,
    gasPriceBid: opts.gasPriceBid ?? gasParams.maxFeePerGas,
    maxSubmissionCost: opts.maxSubmissionCost ?? gasParams.maxSubmissionCost,
  }
}
