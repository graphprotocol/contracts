import yargs, { Argv } from 'yargs'
import { constants, utils, Wallet } from 'ethers'
import { createAttestation, Attestation, Receipt } from '@graphprotocol/common-ts'

import { logger } from '../../logging'
import { sendTransaction, getProvider, toGRT, randomHexBytes } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { getChainID } from '../../network'

const { HashZero } = constants
const { defaultAbiCoder: abi, arrayify, concat, hexlify } = utils

interface ChannelKey {
  privKey: string
  pubKey: string
  address: string
}

async function buildAttestation(receipt: Receipt, signer: string, disputeManagerAddress: string) {
  const attestation = await createAttestation(
    signer,
    getChainID(),
    disputeManagerAddress,
    receipt,
    '0',
  )
  return attestation
}

export const deriveChannelKey = (): ChannelKey => {
  const w = Wallet.createRandom()
  return { privKey: w.privateKey, pubKey: w.publicKey, address: utils.computeAddress(w.publicKey) }
}

function encodeAttestation(attestation: Attestation): string {
  const data = arrayify(
    abi.encode(
      ['bytes32', 'bytes32', 'bytes32'],
      [attestation.requestCID, attestation.responseCID, attestation.subgraphDeploymentID],
    ),
  )
  const sig = concat([
    arrayify(hexlify(attestation.v)),
    arrayify(attestation.r),
    arrayify(attestation.s),
  ])
  return hexlify(concat([data, sig]))
}

async function setupIndexer(
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
  indexerChannelKey: ChannelKey,
  receipt: Receipt,
  accountIndex: number,
) {
  const indexer = Wallet.fromMnemonic(cliArgs.mnemonic, `m/44'/60'/0'/0/${accountIndex}`).connect(
    getProvider(cliArgs.providerUrl),
  )

  const grt = cli.contracts.GraphToken
  const staking = cli.contracts.Staking

  const indexerTokens = toGRT('100000')
  const indexerAllocatedTokens = toGRT('10000')
  const metadata = HashZero

  logger.info('Transferring tokens to the indexer...')
  await sendTransaction(cli.wallet, grt, 'transfer', [indexer.address, indexerTokens])
  logger.info('Approving the staking address to pull tokens...')
  await sendTransaction(cli.wallet, grt, 'approve', [staking.address, indexerTokens])
  logger.info('Staking...')
  await sendTransaction(cli.wallet, staking, 'stake', [indexerTokens])
  logger.info('Allocating...')
  await sendTransaction(cli.wallet, staking, 'allocate', [
    receipt.subgraphDeploymentID,
    indexerAllocatedTokens,
    indexerChannelKey.address,
    metadata,
  ])
}

// This just creates any query dispute conflict to test the subgraph, no real data is sent
export const createTestQueryDisputeConflict = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
): Promise<void> => {
  // Derive some channel keys for each indexer used to sign attestations
  const indexer1ChannelKey = deriveChannelKey()
  const indexer2ChannelKey = deriveChannelKey()

  // Create an attesation receipt for the dispute
  const receipt: Receipt = {
    requestCID: randomHexBytes(),
    responseCID: randomHexBytes(),
    subgraphDeploymentID: randomHexBytes(),
  }

  const receipt1 = receipt
  const receipt2 = { ...receipt1, responseCID: randomHexBytes() }

  await setupIndexer(cli, cliArgs, indexer1ChannelKey, receipt1, 1)
  await setupIndexer(cli, cliArgs, indexer2ChannelKey, receipt2, 2)

  const disputeManager = cli.contracts.DisputeManager
  const disputeManagerAddr = disputeManager.address

  const attestation1 = await buildAttestation(
    receipt1,
    indexer1ChannelKey.privKey,
    disputeManagerAddr,
  )
  const attestation2 = await buildAttestation(
    receipt2,
    indexer2ChannelKey.privKey,
    disputeManagerAddr,
  )

  logger.info(`Creating conflicting attestations...`)
  await sendTransaction(cli.wallet, disputeManager, 'createQueryDisputeConflict', [
    encodeAttestation(attestation1),
    encodeAttestation(attestation2),
  ])
}

// This just creates any indexing dispute to test the subgraph, no real data is sent
export const createTestIndexingDispute = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
): Promise<void> => {
  // Derive some channel keys for each indexer used to sign attestations
  const indexerChannelKey = deriveChannelKey()

  // Create an attesation receipt for the dispute
  const receipt: Receipt = {
    requestCID: randomHexBytes(),
    responseCID: randomHexBytes(),
    subgraphDeploymentID: randomHexBytes(),
  }

  await setupIndexer(cli, cliArgs, indexerChannelKey, receipt, 0)

  // min deposit is 100 GRT, so we do 1000 for safe measure
  const deposit = toGRT('1000')
  const disputeManager = cli.contracts.DisputeManager
  const grt = cli.contracts.GraphToken

  logger.info('Approving the dispute address to pull tokens...')
  await sendTransaction(cli.wallet, grt, 'approve', [disputeManager.address, deposit])

  logger.info(`Creating indexing dispute...`)
  await sendTransaction(cli.wallet, disputeManager, 'createIndexingDispute', [
    indexerChannelKey.address,
    deposit,
  ])
}

export const accept = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const disputeManager = cli.contracts.DisputeManager
  const disputeID = cliArgs.disputeID
  logger.info(`Accepting...`)
  await sendTransaction(cli.wallet, disputeManager, 'acceptDispute', ...[disputeID])
}

export const reject = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const disputeManager = cli.contracts.DisputeManager
  const disputeID = cliArgs.disputeID
  logger.info(`Rejecting...`)
  await sendTransaction(cli.wallet, disputeManager, 'rejectDispute', ...[disputeID])
}

export const draw = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const disputeManager = cli.contracts.DisputeManager
  const disputeID = cliArgs.disputeID
  logger.info(`Drawing...`)
  await sendTransaction(cli.wallet, disputeManager, 'drawDispute', ...[disputeID])
}

export const disputeManagerCommand = {
  command: 'disputeManager',
  describe: 'Dispute manager calls',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'query-dispute-conflict-test',
        describe: 'Just create any query dispute to test the subgraph',
        handler: async (argv: CLIArgs): Promise<void> => {
          return createTestQueryDisputeConflict(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'indexing-dispute-test',
        describe: 'Just create any query dispute to test the subgraph',
        handler: async (argv: CLIArgs): Promise<void> => {
          return createTestIndexingDispute(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'accept',
        describe: 'Accept a dispute',
        builder: (yargs: Argv) => {
          return yargs.option('disputeID', {
            description: 'The Dispute ID in question',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return accept(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'reject',
        describe: 'Reject a dispute',
        builder: (yargs: Argv) => {
          return yargs.option('disputeID', {
            description: 'The Dispute ID in question',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return reject(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'draw',
        describe: 'Draw a dispute',
        builder: (yargs: Argv) => {
          return yargs.option('disputeID', {
            description: 'The Dispute ID in question',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return draw(await loadEnv(argv), argv)
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
