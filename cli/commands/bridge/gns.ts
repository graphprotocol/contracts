import { Argv } from 'yargs'
import { utils } from 'ethers'
import { L1TransactionReceipt } from '@arbitrum/sdk'

import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { logger } from '../../logging'
import { getProvider, sendTransaction, toGRT, ensureAllowance, toBN } from '../../network'
import { chainIdIsL2, estimateRetryableTxGas } from '../../cross-chain'

import { redeemSendToL2 } from './to-l2'
import { checkAndRedeemMessage } from './common'
import { defaultAbiCoder } from 'ethers/lib/utils'
import { getAddressBook } from '../../address-book'
import { loadAddressBookContract } from '../../contracts'
import { L2GNS } from '../../../build/types/L2GNS'

const afterRedeemMsg =
  'Subgraph successfully sent to L2. Finish the migration using finish-send-subgraph-to-l2'

export const sendSubgraphToL2 = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Sending subgraph ${cliArgs.subgraphId} to L2 <<<\n`)

  // parse provider
  const l1Provider = cli.wallet.provider
  // TODO: fix this hack for usage with hardhat
  const l2Provider = cliArgs.l2Provider ? cliArgs.l2Provider : getProvider(cliArgs.l2ProviderUrl)
  const l1ChainId = cli.chainId
  const l2ChainId = (await l2Provider.getNetwork()).chainId
  if (chainIdIsL2(l1ChainId) || !chainIdIsL2(l2ChainId)) {
    throw new Error(
      'Please use an L1 provider in --provider-url, and an L2 provider in --l2-provider-url',
    )
  }

  // parse params
  const { L1GraphTokenGateway: l1Gateway, GraphToken: l1GRT, L1GNS: l1GNS } = cli.contracts

  const recipient = await l1GNS.counterpartGNSAddress()
  const l1GatewayAddress = l1Gateway.address
  const l2GatewayAddress = await l1Gateway.l2Counterpart()
  const l2Owner = cliArgs.l2Owner ?? cli.wallet.address
  const nSignal = await l1GNS.subgraphSignal(cliArgs.subgraphId)
  const tokens = await l1GNS.subgraphTokens(cliArgs.subgraphId)
  const calldata = defaultAbiCoder.encode(
    ['uint256', 'address', 'uint256'],
    [cliArgs.subgraphId, l2Owner, nSignal],
  )

  // estimate L2 ticket
  // See https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-ts/src/lib/bridge.ts
  const depositCalldata = await l1Gateway.getOutboundCalldata(
    l1GRT.address,
    l1GNS.address,
    recipient,
    tokens,
    calldata,
  )
  const { maxGas, gasPriceBid, maxSubmissionCost } = await estimateRetryableTxGas(
    l1Provider,
    l2Provider,
    l1GatewayAddress,
    l2GatewayAddress,
    depositCalldata,
    {
      maxGas: cliArgs.maxGas,
      gasPriceBid: cliArgs.gasPriceBid,
      maxSubmissionCost: cliArgs.maxSubmissionCost,
    },
  )
  const ethValue = maxSubmissionCost.add(gasPriceBid.mul(maxGas))
  logger.info(
    `Using maxGas:${maxGas}, gasPriceBid:${gasPriceBid}, maxSubmissionCost:${maxSubmissionCost} = tx value: ${ethValue}`,
  )

  // build transaction
  logger.info('Sending outbound transfer transaction')

  const txParams = [cliArgs.subgraphId, l2Owner, maxGas, gasPriceBid, maxSubmissionCost]
  const txReceipt = await sendTransaction(cli.wallet, l1GNS, 'sendSubgraphToL2', txParams, {
    value: ethValue,
  })

  // get l2 ticket status
  if (txReceipt.status == 1) {
    logger.info('Waiting for message to propagate to L2...')
    const l1Receipt = new L1TransactionReceipt(txReceipt)
    const l1ToL2Messages = await l1Receipt.getL1ToL2Messages(cli.wallet.connect(l2Provider))
    const l1ToL2Message = l1ToL2Messages[0]
    try {
      await checkAndRedeemMessage(l1ToL2Message)
      logger.info(afterRedeemMsg)
    } catch (e) {
      logger.error('Auto redeem failed')
      logger.error(e)
      logger.error('You can re-attempt using redeem-send-subgraph-to-l2 with the following txHash:')
      logger.error(txReceipt.transactionHash)
    }
  }
}

export const redeemSendSubgraphToL2 = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
): Promise<void> => {
  await redeemSendToL2(cli, cliArgs)
  logger.info(afterRedeemMsg)
}

export const finishSendSubgraphToL2 = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
): Promise<void> => {
  logger.info(`>>> Finishing migration for subgraph ${cliArgs.subgraphId} on L2 <<<\n`)

  // TODO: fix this hack for usage with hardhat
  const l2Provider = cliArgs.l2Provider ? cliArgs.l2Provider : getProvider(cliArgs.l2ProviderUrl)
  const l1ChainId = cli.chainId
  const l2ChainId = (await l2Provider.getNetwork()).chainId
  if (chainIdIsL2(l1ChainId) || !chainIdIsL2(l2ChainId)) {
    throw new Error(
      'Please use an L1 provider in --provider-url, and an L2 provider in --l2-provider-url',
    )
  }
  const l2Wallet = cli.wallet.connect(l2Provider)
  const l2AddressBook = getAddressBook(cliArgs.addressBook, l2ChainId.toString())

  const l2GNS = loadAddressBookContract('L2GNS', l2AddressBook, l2Wallet) as L2GNS

  const txParams = [
    cliArgs.subgraphId,
    cliArgs.subgraphDeploymentId,
    cliArgs.subgraphMetadata,
    cliArgs.versionMetadata,
  ]

  logger.info('Finishing the subgraph migration on L2GNS')
  await sendTransaction(l2Wallet, l2GNS, 'finishSubgraphMigrationFromL1', txParams)
}

export const claimCuratorBalanceOnL2 = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
): Promise<void> => {
  logger.info(`>>> Claiming balance for subgraph ${cliArgs.subgraphId} on L2 <<<\n`)

  // parse provider
  const l1Provider = cli.wallet.provider
  // TODO: fix this hack for usage with hardhat
  const l2Provider = cliArgs.l2Provider ? cliArgs.l2Provider : getProvider(cliArgs.l2ProviderUrl)
  const l1ChainId = cli.chainId
  const l2ChainId = (await l2Provider.getNetwork()).chainId
  if (chainIdIsL2(l1ChainId) || !chainIdIsL2(l2ChainId)) {
    throw new Error(
      'Please use an L1 provider in --provider-url, and an L2 provider in --l2-provider-url',
    )
  }

  // parse params
  const { GraphToken: l1GRT, L1GNS: l1GNS } = cli.contracts

  const recipient = await l1GNS.counterpartGNSAddress()
  const l2Beneficiary = cliArgs.l2Beneficiary ?? cli.wallet.address

  // estimate L2 ticket
  // See https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-ts/src/lib/bridge.ts
  const depositCalldata = await l1GNS.getClaimCuratorBalanceOutboundCalldata(
    cliArgs.subgraphId,
    cli.wallet.address,
    l2Beneficiary,
  )
  console.log(depositCalldata)
  const { maxGas, gasPriceBid, maxSubmissionCost } = await estimateRetryableTxGas(
    l1Provider,
    l2Provider,
    l1GNS.address,
    recipient,
    depositCalldata,
    {
      maxGas: cliArgs.maxGas,
      gasPriceBid: cliArgs.gasPriceBid,
      maxSubmissionCost: cliArgs.maxSubmissionCost,
    },
  )
  const ethValue = maxSubmissionCost.add(gasPriceBid.mul(maxGas))
  logger.info(
    `Using maxGas:${maxGas}, gasPriceBid:${gasPriceBid}, maxSubmissionCost:${maxSubmissionCost} = tx value: ${ethValue}`,
  )

  // build transaction
  logger.info('Sending outbound transfer transaction')

  const txParams = [cliArgs.subgraphId, l2Beneficiary, maxGas, gasPriceBid, maxSubmissionCost]
  const txReceipt = await sendTransaction(
    cli.wallet,
    l1GNS,
    'claimCuratorBalanceToBeneficiaryOnL2',
    txParams,
    {
      value: ethValue,
    },
  )

  // get l2 ticket status
  if (txReceipt.status == 1) {
    logger.info('Waiting for message to propagate to L2...')
    const l1Receipt = new L1TransactionReceipt(txReceipt)
    const l1ToL2Messages = await l1Receipt.getL1ToL2Messages(cli.wallet.connect(l2Provider))
    const l1ToL2Message = l1ToL2Messages[0]
    try {
      await checkAndRedeemMessage(l1ToL2Message)
    } catch (e) {
      logger.error('Auto redeem failed')
      logger.error(e)
      logger.error('You can re-attempt using redeem-send-to-l2 with the following txHash:')
      logger.error(txReceipt.transactionHash)
    }
  }
}

export const sendToL2Command = {
  command: 'send-subgraph-to-l2 <subgraph-id> [l2-owner]',
  describe: 'Migrate a subgraph from L1 to L2',
  builder: (yargs: Argv): Argv => {
    return yargs
      .option('max-gas', {
        description: 'Max gas for the L2 redemption attempt',
        requiresArg: true,
        type: 'string',
      })
      .option('gas-price-bid', {
        description: 'Gas price for the L2 redemption attempt',
        requiresArg: true,
        type: 'string',
      })
      .option('max-submission-cost', {
        description: 'Max submission cost for the retryable ticket',
        requiresArg: true,
        type: 'string',
      })
      .positional('subgraph-id', { description: 'Subgraph ID to migrate' })
      .positional('l2-owner', {
        description: 'Address that will own the subgraph on L2. Same as L1 address if empty',
      })
      .coerce({
        subgraphId: toBN,
        maxGas: toBN,
        gasPriceBid: toBN,
        maxSubmissionCost: toBN,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return sendSubgraphToL2(await loadEnv(argv), argv)
  },
}

export const redeemSendSubgraphToL2Command = {
  command: 'redeem-send-subgraph-to-l2 <txHash>',
  describe: 'Redeem an L1-to-L2 subgraph migration ticket if it failed to autoredeem',
  handler: async (argv: CLIArgs): Promise<void> => {
    return redeemSendSubgraphToL2(await loadEnv(argv), argv)
  },
}
export const finishSendSubgraphToL2Command = {
  command:
    'finish-send-subgraph-to-l2 <subgraph-id> <subgraph-deployment-id> <subgraph-metadata> <version-metadata>',
  describe: 'Finish an L1-to-L2 subgraph migration',
  handler: async (argv: CLIArgs): Promise<void> => {
    return finishSendSubgraphToL2(await loadEnv(argv), argv)
  },
}

export const claimCuratorBalanceOnL2Command = {
  command: 'claim-curator-balance-on-l2 <subgraph-id> [l2-beneficiary]',
  describe: 'Claim curator balance for a subgraph that was migrated to L2',
  builder: (yargs: Argv): Argv => {
    return yargs
      .option('max-gas', {
        description: 'Max gas for the L2 redemption attempt',
        requiresArg: true,
        type: 'string',
      })
      .option('gas-price-bid', {
        description: 'Gas price for the L2 redemption attempt',
        requiresArg: true,
        type: 'string',
      })
      .option('max-submission-cost', {
        description: 'Max submission cost for the retryable ticket',
        requiresArg: true,
        type: 'string',
      })
      .positional('subgraph-id', { description: 'Subgraph ID to migrate' })
      .positional('l2-beneficiary', {
        description: 'Address that will own the signal on L2. Same as L1 address if empty',
      })
      .coerce({
        subgraphId: toBN,
        maxGas: toBN,
        gasPriceBid: toBN,
        maxSubmissionCost: toBN,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return claimCuratorBalanceOnL2(await loadEnv(argv), argv)
  },
}
