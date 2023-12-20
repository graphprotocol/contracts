import fs from 'fs'
import PQueue from 'p-queue'
import yargs, { Argv } from 'yargs'
import { parseGRT, formatGRT } from '@graphprotocol/common-ts'

import { utils, BigNumber, Contract } from 'ethers'
import { NonceManager } from '@ethersproject/experimental'

import { logger } from '../logging'
import { sendTransaction } from '../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../env'
import { confirm } from '../helpers'

const { getAddress } = utils

const DISPERSE_CONTRACT_ADDRESS = {
  1: '0xD152f549545093347A162Dce210e7293f1452150',
  4: '0xD152f549545093347A162Dce210e7293f1452150',
  1337: '0xD152f549545093347A162Dce210e7293f1452150',
}

const DISPERSE_CONTRACT_ABI = [
  {
    constant: false,
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'recipients', type: 'address[]' },
      { name: 'values', type: 'uint256[]' },
    ],
    name: 'disperseTokenSimple',
    outputs: [],
    payable: false,
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    constant: false,
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'recipients', type: 'address[]' },
      { name: 'values', type: 'uint256[]' },
    ],
    name: 'disperseToken',
    outputs: [],
    payable: false,
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    constant: false,
    inputs: [
      { name: 'recipients', type: 'address[]' },
      { name: 'values', type: 'uint256[]' },
    ],
    name: 'disperseEther',
    outputs: [],
    payable: true,
    stateMutability: 'payable',
    type: 'function',
  },
]

interface AirdropRecipient {
  address: string
  amount: BigNumber
  txHash?: string
}

const getDisperseContract = (chainID: number, provider) => {
  return new Contract(DISPERSE_CONTRACT_ADDRESS[chainID], DISPERSE_CONTRACT_ABI, provider)
}

const loadRecipients = (path: string): Array<AirdropRecipient> => {
  const data = fs.readFileSync(path, 'utf8')
  const lines = data.split('\n').map((e) => e.trim())

  const results: Array<AirdropRecipient> = []
  for (const line of lines) {
    const [address, amount, txHash] = line.split(',').map((e) => e.trim())

    // Skip any empty value
    if (!address) continue

    // Test for zero amount and fail
    const weiAmount = parseGRT(amount)
    if (weiAmount.eq(0)) {
      logger.crit(`Error loading address "${address}" - amount is zero`)
      process.exit(0)
    }

    // Validate address format
    try {
      getAddress(address)
    } catch (err) {
      // Full stop on error
      logger.crit(`Error loading address "${address}" please review the input file`)
      process.exit(1)
    }
    results.push({ address, amount: weiAmount, txHash })
  }
  return results
}

const sumTotalAmount = (recipients: Array<AirdropRecipient>): BigNumber => {
  let total = BigNumber.from(0)
  for (const recipient of recipients) {
    total = total.add(recipient.amount)
  }
  return total
}

const saveResumeList = (path: string, txHash: string, recipients: Array<AirdropRecipient>) => {
  for (const recipient of recipients) {
    const line = [recipient.address, formatGRT(recipient.amount), txHash].join(',') + '\n'
    fs.writeFileSync(path, line, {
      flag: 'a+',
    })
  }
}

const loadResumeList = (path: string): Array<AirdropRecipient> => {
  try {
    return loadRecipients(path)
  } catch (err) {
    if (err.code === 'ENOENT') {
      logger.warn('No existing resumefile, one will be created')
      return []
    } else {
      throw err
    }
  }
}

const createBatches = (
  items: Array<AirdropRecipient>,
  batchSize = 10,
): Array<Array<AirdropRecipient>> => {
  const remainingItems = Object.assign([], items)
  const batches = []
  while (remainingItems.length > 0) {
    const batchItems = remainingItems.splice(0, batchSize)
    batches.push(batchItems)
    if (batchItems.length < batchSize) {
      break
    }
  }
  return batches
}

export const airdrop = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const graphToken = cli.contracts.GraphToken
  const skipConfirmation = cliArgs.skipConfirmation

  // Load data
  const resumeList = loadResumeList(cliArgs.resumefile).map((r) => r.address)
  const recipients = loadRecipients(cliArgs.recipients).filter(
    (r) => !resumeList.includes(r.address),
  )
  const totalAmount = sumTotalAmount(recipients)

  // Summary
  logger.info(`# Batch Size: ${cliArgs.batchSize}`)
  logger.info(`# Concurrency: ${cliArgs.concurrency}`)
  logger.info(`> Token: ${graphToken.address}`)
  logger.info(`> Distributing: ${formatGRT(totalAmount)} tokens (${totalAmount} wei)`)
  logger.info(`> Resumelist: ${resumeList.length} addresses`)
  logger.info(`> Recipients: ${recipients.length} addresses\n`)

  // Validity check
  if (totalAmount.eq(0)) {
    logger.crit('Cannot proceed with a distribution of zero tokens')
    process.exit(1)
  }

  // Load airdrop contract
  const disperseContract = getDisperseContract(cli.chainId, cli.wallet.provider)
  if (!disperseContract.address) {
    logger.crit('Disperse contract not found. Please review your network settings.')
    process.exit(1)
  }

  // Confirmation
  const sure = await confirm(
    'Are you sure you want to proceed with the distribution?',
    skipConfirmation,
  )
  if (!sure) return

  // Approve
  logger.info('## Token approval')
  const allowance = (
    await graphToken.functions['allowance'](cli.wallet.address, disperseContract.address)
  )[0]
  if (allowance.gte(totalAmount)) {
    logger.info('Already have enough allowance, no need to approve more...')
  } else {
    logger.info(
      `Approve disperse:${disperseContract.address} for ${formatGRT(
        totalAmount,
      )} tokens (${totalAmount} wei)`,
    )
    await sendTransaction(cli.wallet, graphToken, 'approve', [
      disperseContract.address,
      totalAmount,
    ])
  }

  // Distribute
  logger.info('## Distribution')
  const queue = new PQueue({ concurrency: cliArgs.concurrency })
  const recipientsBatches = createBatches(recipients, cliArgs.batchSize)
  const nonceManager = new NonceManager(cli.wallet) // Use NonceManager to send concurrent txs

  let batchNum = 0
  let recipientsCount = 0
  for (const batch of recipientsBatches) {
    queue.add(async () => {
      const addressList = batch.map((r) => r.address)
      const amountList = batch.map((r) => r.amount)

      recipientsCount += addressList.length
      batchNum++
      logger.info(`Sending batch #${batchNum} : ${recipientsCount}/${recipients.length}`)
      for (const recipient of batch) {
        logger.info(
          `  > Transferring ${recipient.address} => ${formatGRT(recipient.amount)} (${
            recipient.amount
          } wei)`,
        )
      }
      try {
        const receipt = await sendTransaction(nonceManager, disperseContract, 'disperseToken', [
          graphToken.address,
          addressList,
          amountList,
        ])
        saveResumeList(cliArgs.resumefile, receipt.transactionHash, batch)
      } catch (err) {
        logger.error(`Failed to send #${batchNum}`, err)
      }
    })
  }
  await queue.onIdle()
}

export const airdropCommand = {
  command: 'airdrop',
  describe: 'Airdrop tokens',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .option('recipients', {
        description: 'Path to the file with information for the airdrop. CSV file address,amount',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('resumefile', {
        description:
          'Path to the file used for resuming. Stores results with CSV format: address,amount,txHash',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('batch-size', {
        description: 'Number of addresses to send in a single transaction',
        type: 'number',
        requiresArg: true,
        demandOption: true,
        default: 100,
      })
      .option('concurrency', {
        description: 'Number of simultaneous transfers',
        type: 'number',
        requiresArg: true,
        demandOption: false,
        default: 1,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return airdrop(await loadEnv(argv), argv)
  },
}
