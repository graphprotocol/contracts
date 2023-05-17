import { Argv } from 'yargs'

import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { logger } from '../../logging'
import { getProvider, sendTransaction, toBN } from '../../network'
import { chainIdIsL2, estimateRetryableTxGas } from '../../cross-chain'
import { getL1ToL2MessageWriter } from '../../arbitrum'
import { checkAndRedeemMessage, ifNotNullToBN } from './utils'
import { defaultAbiCoder } from 'ethers/lib/utils'
import { getAddressBook } from '../../address-book'
import { loadAddressBookContract } from '../../contracts'
import { L2GNS } from '../../../build/types/L2GNS'

export const sendSubgraphToL2 = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Sending subgraph to L2 <<<\n`)

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
  const subgraphId = cliArgs.subgraphId
  const beneficiary = cliArgs.beneficiary ?? cli.wallet.address
  const l1GatewayAddress = l1Gateway.address
  const l2GatewayAddress = await l1Gateway.l2Counterpart()
  const l1GNSAddress = l1GNS.address
  const l2GNSAddress = await l1GNS.counterpartGNSAddress()
  const ownerSignal = await l1GNS.getCuratorSignal(subgraphId, cli.wallet.address)
  const ownerGRT = (await l1GNS.nSignalToTokens(subgraphId, ownerSignal))[1]

  // Build calldata based on subgraphId and what the L1GNS would use
  const calldata = defaultAbiCoder.encode(
    ['uint8', 'uint256', 'address'],
    [toBN(0), subgraphId, beneficiary], // code = 0 means RECEIVE_SUBGRAPH_CODE
  )

  // transport tokens
  logger.info(`Will send subgraph ${subgraphId} with ${ownerGRT} GRT to ${beneficiary}`)
  logger.info(`Using L1 gateway ${l1GatewayAddress} and L2 gateway ${l2GatewayAddress}`)

  // estimate L2 ticket
  // See https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-ts/src/lib/bridge.ts
  const depositCalldata = await l1Gateway.getOutboundCalldata(
    l1GRT.address,
    l1GNSAddress,
    l2GNSAddress,
    ownerGRT,
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
  logger.info('Sending sendSubgraphToL2 transaction')
  const txParams = [subgraphId, beneficiary, maxGas, gasPriceBid, maxSubmissionCost]
  const txReceipt = await sendTransaction(cli.wallet, l1GNS, 'sendSubgraphToL2', txParams, {
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

export const sendCurationToL2 = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Sending curation to L2 <<<\n`)

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
  const subgraphId = cliArgs.subgraphId
  const beneficiary = cliArgs.beneficiary ?? cli.wallet.address
  const l1GatewayAddress = l1Gateway.address
  const l2GatewayAddress = await l1Gateway.l2Counterpart()
  const l1GNSAddress = l1GNS.address
  const l2GNSAddress = await l1GNS.counterpartGNSAddress()
  const curatorSignal = await l1GNS.getCuratorSignal(subgraphId, cli.wallet.address)
  const l1Subgraph = await l1GNS.subgraphs(subgraphId)
  const nSignal = l1Subgraph.nSignal
  const totalTokens = l1Subgraph.withdrawableGRT
  const curatorGRT = curatorSignal.mul(totalTokens).div(nSignal)

  // Build calldata based on subgraphId and what the L1GNS would use
  const calldata = defaultAbiCoder.encode(
    ['uint8', 'uint256', 'address'],
    [toBN(1), subgraphId, beneficiary], // code = 1 means RECEIVE_CURATION_CODE
  )

  // transport tokens
  logger.info(
    `Will send signal from ${cli.wallet.address} for subgraph ${subgraphId} to ${beneficiary} on L2`,
  )
  logger.info(`Sending ${curatorGRT} GRT`)
  logger.info(`Using L1 gateway ${l1GatewayAddress} and L2 gateway ${l2GatewayAddress}`)

  // estimate L2 ticket
  // See https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-ts/src/lib/bridge.ts
  const depositCalldata = await l1Gateway.getOutboundCalldata(
    l1GRT.address,
    l1GNSAddress,
    l2GNSAddress,
    curatorGRT,
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
  logger.info('Sending sendCuratorBalanceToBeneficiaryOnL2 transaction')
  const txParams = [subgraphId, beneficiary, maxGas, gasPriceBid, maxSubmissionCost]
  const txReceipt = await sendTransaction(
    cli.wallet,
    l1GNS,
    'sendCuratorBalanceToBeneficiaryOnL2',
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

export const finishSubgraphTransferToL2 = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
): Promise<void> => {
  logger.info(`>>> Finishing subgraph transfer to L2 <<<\n`)

  // parse provider
  const l1Provider = cli.wallet.provider

  const l2Provider = getProvider(cliArgs.l2ProviderUrl)
  const l1ChainId = cli.chainId
  const l2ChainId = (await l2Provider.getNetwork()).chainId
  if (chainIdIsL2(l1ChainId) || !chainIdIsL2(l2ChainId)) {
    throw new Error(
      'Please use an L1 provider in --provider-url, and an L2 provider in --l2-provider-url',
    )
  }

  // parse params
  const { L1GNS: l1GNS } = cli.contracts
  const l1SubgraphId = cliArgs.l1SubgraphId

  const l2Wallet = cli.wallet.connect(l2Provider)
  const l2AddressBook = getAddressBook(cliArgs.addressBook, l2ChainId.toString())

  const l2GNS = loadAddressBookContract('L2GNS', l2AddressBook, l2Wallet) as L2GNS

  // get L2 subgraph ID
  const l2SubgraphId = await l2GNS.getAliasedL2SubgraphID(l1SubgraphId)

  const l1Subgraph = await l1GNS.subgraphs(l1SubgraphId)

  const params = [
    l2SubgraphId,
    l1Subgraph.subgraphDeploymentID,
    cliArgs.subgraphMetadata,
    cliArgs.versionMetadata,
  ]

  logger.info(
    `Finishing transfer for subgraph ID ${l1SubgraphId} to L2 subgraph ID ${l2SubgraphId}`,
  )
  logger.info(
    `Using deployment ID ${l1Subgraph.subgraphDeploymentID}, subgraph metadata ${cliArgs.subgraphMetadata}, and version metadata ${cliArgs.versionMetadata}`,
  )
  logger.info(`To L2GNS at ${l2GNS.address}`)
  await sendTransaction(l2Wallet, l2GNS, 'finishSubgraphTransferFromL1', params)
}

export const finishSubgraphTransferToL2Command = {
  command: 'finish-subgraph-transfer-to-l2 <l1SubgraphId> <versionMetadata> <subgraphMetadata>',
  describe: 'Finish an L1-to-L2 subgraph transfer',
  builder: (yargs: Argv): Argv => {
    return yargs
      .positional('l1SubgraphId', { description: 'Subgraph ID on L1' })
      .positional('versionMetadata', { description: 'IPFS hash for the subgraph version metadata' })
      .positional('subgraphMetadata', { description: 'IPFS hash for the subgraph metadata' })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return finishSubgraphTransferToL2(await loadEnv(argv), argv)
  },
}

export const sendSubgraphToL2Command = {
  command: 'send-subgraph-to-l2 <subgraphId> [beneficiary]',
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
      .positional('subgraphId', { description: 'Subgraph ID to send' })
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
    return sendSubgraphToL2(await loadEnv(argv), argv)
  },
}

export const sendCurationToL2Command = {
  command: 'send-curation-to-l2 <subgraphId> [beneficiary]',
  describe: 'Send curation from an L1 subgraph to L2',
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
      .positional('subgraphId', { description: 'Subgraph ID to send' })
      .positional('beneficiary', {
        description:
          'Receiving address for the curation signal in L2. Same to L1 wallet address if empty',
      })
      .coerce({
        maxGas: ifNotNullToBN,
        gasPriceBid: ifNotNullToBN,
        maxSubmissionCost: ifNotNullToBN,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return sendCurationToL2(await loadEnv(argv), argv)
  },
}
