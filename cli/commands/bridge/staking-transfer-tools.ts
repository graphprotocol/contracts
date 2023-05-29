import { Argv } from 'yargs'

import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { logger } from '../../logging'
import { getProvider, sendTransaction, toBN, toGRT } from '../../network'
import { chainIdIsL2, estimateRetryableTxGas } from '../../cross-chain'
import { getL1ToL2MessageWriter } from '../../arbitrum'
import { checkAndRedeemMessage, ifNotNullToBN } from './utils'
import { Interface, defaultAbiCoder, formatUnits } from 'ethers/lib/utils'
import { getAddressBook } from '../../address-book'
import { loadAddressBookContract } from '../../contracts'
import { L2GNS } from '../../../build/types/L2GNS'
import { L1Staking } from '../../../build/types/L1Staking'
import { loadArtifact } from '../../artifacts'
import { Contract } from 'ethers'

export const sendStakeToL2 = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Sending stake to L2 <<<\n`)

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
  const { L1GraphTokenGateway: l1Gateway, GraphToken: l1GRT, L1Staking: l1Staking } = cli.contracts
  const amount = toGRT(cliArgs.amount)
  const beneficiary = cliArgs.beneficiary ?? cli.wallet.address
  const l1GatewayAddress = l1Gateway.address
  const l2GatewayAddress = await l1Gateway.l2Counterpart()
  const l1StakingAddress = l1Staking.address

  const l2AddressBook = getAddressBook(cliArgs.addressBook, l2ChainId.toString())
  const l2StakingAddress = l2AddressBook.getEntry('L2Staking').address

  const functionData = defaultAbiCoder.encode(['tuple(address)'], [[beneficiary]])

  const calldata = defaultAbiCoder.encode(
    ['uint8', 'bytes'],
    [toBN(0), functionData], // code = 0 means RECEIVE_INDEXER_CODE
  )

  // transport tokens
  logger.info(
    `Will send ${cliArgs.amount} GRT of stake from ${cli.wallet.address} to ${beneficiary}`,
  )
  logger.info(`Using L1 gateway ${l1GatewayAddress} and L2 gateway ${l2GatewayAddress}`)

  // estimate L2 ticket
  // See https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-ts/src/lib/bridge.ts
  const depositCalldata = await l1Gateway.getOutboundCalldata(
    l1GRT.address,
    l1StakingAddress,
    l2StakingAddress,
    amount,
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
  logger.info('Sending transferStakeToL2 transaction')
  const txParams = [beneficiary, amount, maxGas, gasPriceBid, maxSubmissionCost]
  const txReceipt = await sendTransaction(cli.wallet, l1Staking, 'transferStakeToL2', txParams, {
    value: ethValue,
  })

  // get l2 ticket status
  if (txReceipt.status == 1) {
    logger.info('Waiting for message to propagate to L2...')
    const l1ToL2Message = await getL1ToL2MessageWriter(
      txReceipt,
      cli.wallet.provider,
      l2Provider,
      cli.wallet,
    )
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

export const sendDelegationToL2 = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Sending delegation to L2 <<<\n`)

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
  const { L1GraphTokenGateway: l1Gateway, GraphToken: l1GRT, L1Staking: l1Staking } = cli.contracts
  const beneficiary = cliArgs.beneficiary ?? cli.wallet.address
  const l1GatewayAddress = l1Gateway.address
  const l2GatewayAddress = await l1Gateway.l2Counterpart()
  const l1StakingAddress = l1Staking.address

  const l2AddressBook = getAddressBook(cliArgs.addressBook, l2ChainId.toString())
  const l2StakingAddress = l2AddressBook.getEntry('L2Staking').address

  const iface = new Interface(loadArtifact('L1Staking').abi)
  const l1StakingWithIface = new Contract(
    l1StakingAddress,
    iface,
    l1Provider,
  ) as unknown as L1Staking
  const l2Indexer = await l1StakingWithIface.indexerTransferredToL2(cliArgs.indexer)
  const functionData = defaultAbiCoder.encode(
    ['tuple(address,address)'],
    [[l2Indexer, beneficiary]],
  )
  const calldata = defaultAbiCoder.encode(
    ['uint8', 'bytes'],
    [toBN(1), functionData], // code = 1 means RECEIVE_DELEGATION_CODE
  )
  const pool = await l1Staking.delegationPools(cliArgs.indexer)
  const shares = (await l1Staking.getDelegation(cliArgs.indexer, cli.wallet.address)).shares
  const amount = shares.mul(pool.tokens).div(pool.shares)

  // transport tokens
  logger.info(
    `Will send delegation from ${cli.wallet.address} for L1 indexer ${cliArgs.indexer} to ${beneficiary} on L2`,
  )

  logger.info(`Sending ${formatUnits(amount, '18')} GRT, delegated to L2 indexer ${l2Indexer}`)
  logger.info(`Using L1 gateway ${l1GatewayAddress} and L2 gateway ${l2GatewayAddress}`)

  // estimate L2 ticket
  // See https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-ts/src/lib/bridge.ts
  const depositCalldata = await l1Gateway.getOutboundCalldata(
    l1GRT.address,
    l1StakingAddress,
    l2StakingAddress,
    amount,
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
  logger.info('Sending transferDelegationToL2 transaction')
  const txParams = [cliArgs.indexer, beneficiary, maxGas, gasPriceBid, maxSubmissionCost]
  const txReceipt = await sendTransaction(
    cli.wallet,
    l1Staking,
    'transferDelegationToL2',
    txParams,
    {
      value: ethValue,
    },
  )

  // get l2 ticket status
  if (txReceipt.status == 1) {
    logger.info('Waiting for message to propagate to L2...')
    const l1ToL2Message = await getL1ToL2MessageWriter(
      txReceipt,
      cli.wallet.provider,
      l2Provider,
      cli.wallet,
    )
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

export const sendStakeToL2Command = {
  command: 'send-stake-to-l2 <amount> [beneficiary]',
  describe: 'Send an L1 subgraph to L2',
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
      .positional('amount', { description: 'Amount of GRT to send' })
      .positional('beneficiary', {
        description: 'Receiving address in L2. Same to L1 owner address if empty',
      })
      .coerce({
        maxGas: ifNotNullToBN,
        gasPriceBid: ifNotNullToBN,
        maxSubmissionCost: ifNotNullToBN,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return sendStakeToL2(await loadEnv(argv), argv)
  },
}

export const sendDelegationToL2Command = {
  command: 'send-delegation-to-l2 <indexer> [beneficiary]',
  describe: 'Send delegation from an L1 indexer to L2',
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
      .positional('indexer', { description: 'L1 address of the indexer' })
      .positional('beneficiary', {
        description:
          'Receiving address for the delegation in L2. Same to L1 wallet address if empty',
      })
      .coerce({
        maxGas: ifNotNullToBN,
        gasPriceBid: ifNotNullToBN,
        maxSubmissionCost: ifNotNullToBN,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return sendDelegationToL2(await loadEnv(argv), argv)
  },
}
