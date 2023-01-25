import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { ethers } from 'ethers'
import { Table } from 'console-table-printer'
import { L1ToL2MessageStatus } from '@arbitrum/sdk'
import { getL1ToL2MessageStatus, getL1ToL2MessageReader } from '../../cli/arbitrum'

export const TASK_BRIDGE_DEPOSITS = 'bridge:deposits'

task(TASK_BRIDGE_DEPOSITS, 'List deposits initiated on L1GraphTokenGateway')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam(
    'arbitrumAddressBook',
    cliOpts.arbitrumAddressBook.description,
    cliOpts.arbitrumAddressBook.default,
  )
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l1StartBlock', 'Start block on L1 for the search')
  .addOptionalParam('l1EndBlock', 'End block on L1 for the search')
  .addOptionalParam('l2StartBlock', 'Start block on L2 for the search')
  .setAction(async (taskArgs, hre) => {
    console.time('runtime')
    console.log('> GRT Bridge deposits <\n')

    const graph = hre.graph(taskArgs)
    const l2Gateway = graph.l2.contracts.L2GraphTokenGateway
    const l1Gateway = graph.l1.contracts.L1GraphTokenGateway
    const l1StartBlock = taskArgs.l1StartBlock ? parseInt(taskArgs.l1StartBlock) : 0
    const l1EndBlock = taskArgs.l1EndBlock ? parseInt(taskArgs.l1EndBlock) : 'latest'
    const l2StartBlock = taskArgs.l2StartBlock ? parseInt(taskArgs.l2StartBlock) : 0

    console.log(
      `Tracking 'DepositInitiated' events on L1GraphTokenGateway (${l1Gateway.address}) from block ${l1StartBlock} to block ${l1EndBlock}`,
    )
    console.log(
      `Tracking 'DepositFinalized' events on L2GraphTokenGateway (${l2Gateway.address}) from block ${l2StartBlock} onwards`,
    )

    const amount = await (
      await l1Gateway.queryFilter(l1Gateway.filters.DepositInitiated(), l1StartBlock, l1EndBlock)
    ).length
    console.log(`Found ${amount} deposits on L1`)

    const depositInitiatedEvents = await Promise.all(
      (
        await l1Gateway.queryFilter(l1Gateway.filters.DepositInitiated(), l1StartBlock, l1EndBlock)
      ).map(async (e) => {
        const retryableTicket = await getL1ToL2MessageReader(
          e.transactionHash,
          graph.l1.provider,
          graph.l2.provider,
        )

        return {
          l1Tx: `Block ${e.blockNumber} (${new Date(
            (await graph.l1.provider.getBlock(e.blockNumber)).timestamp * 1000,
          ).toLocaleString()}) ${e.transactionHash}`,
          l2Tx: `${retryableTicket.retryableCreationId}`, // Can't get block data because of arb node rate limit
          amount: prettyBigNumber(e.args.amount),
          status: emojifyRetryableStatus(
            await getL1ToL2MessageStatus(e.transactionHash, graph.l1.provider, graph.l2.provider),
          ),
        }
      }),
    )

    const total = depositInitiatedEvents.reduce(
      (acc, e) => acc.add(ethers.utils.parseEther(e.amount)),
      ethers.BigNumber.from(0),
    )
    console.log(
      `Found ${depositInitiatedEvents.length} deposits with a total of ${prettyBigNumber(
        total,
      )} GRT`,
    )

    console.log(
      '\nL1 to L2 message status reference: 🚧 = not yet created, ❌ = creation failed, ⚠️  = funds deposited on L2, ✅ = redeemed, ⌛ = expired',
    )

    printEvents(depositInitiatedEvents)
    console.timeEnd('runtime')
  })

function printEvents(events: any[]) {
  const tablePrinter = new Table({
    charLength: { '🚧': 2, '✅': 2, '⚠️': 1, '⌛': 2, '❌': 2 },
    columns: [
      { name: 'status', color: 'green', alignment: 'center' },
      { name: 'l1Tx', color: 'green', alignment: 'center', maxLen: 72, title: 'L1 transaction' },
      {
        name: 'l2Tx',
        color: 'green',
        alignment: 'center',
        maxLen: 72,
        title: 'L2 retryable ticket creation',
      },
      { name: 'amount', color: 'green' },
    ],
  })

  events.map((e) => {
    tablePrinter.addRow(e)
    tablePrinter.addRow({}) // For table padding
  })
  tablePrinter.printTable()
}

function emojifyRetryableStatus(status: L1ToL2MessageStatus): string {
  switch (status) {
    case L1ToL2MessageStatus.NOT_YET_CREATED:
      return '🚧'
    case L1ToL2MessageStatus.CREATION_FAILED:
      return '❌'
    case L1ToL2MessageStatus.FUNDS_DEPOSITED_ON_L2:
      return '⚠️ '
    case L1ToL2MessageStatus.REDEEMED:
      return '✅'
    case L1ToL2MessageStatus.EXPIRED:
      return '⌛'
    default:
      return '❌'
  }
}

// Format BigNumber to 2 decimal places
function prettyBigNumber(amount: ethers.BigNumber): string {
  return (+ethers.utils.formatEther(amount)).toFixed(2)
}
