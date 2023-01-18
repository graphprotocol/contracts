import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { BigNumber, ethers } from 'ethers'
import { Table } from 'console-table-printer'
import { L2ToL1MessageStatus } from '@arbitrum/sdk'
import { getL2ToL1MessageStatus } from '../../cli/arbitrum'
import { keccak256 } from 'ethers/lib/utils'

export const TASK_BRIDGE_WITHDRAWALS = 'bridge:withdrawals'

task(TASK_BRIDGE_WITHDRAWALS, 'List withdrawals initiated on L2GraphTokenGateway')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam(
    'arbitrumAddressBook',
    cliOpts.arbitrumAddressBook.description,
    cliOpts.arbitrumAddressBook.default,
  )
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l1StartBlock', 'Start block on L1 for the search')
  .addOptionalParam('l2StartBlock', 'Start block on L2 for the search')
  .addOptionalParam('l2EndBlock', 'End block on L2 for the search')
  .setAction(async (taskArgs, hre) => {
    console.time('runtime')
    console.log('> GRT Bridge withdrawals <\n')

    const graph = hre.graph(taskArgs)
    const l2Gateway = graph.l2.contracts.L2GraphTokenGateway
    const l1Gateway = graph.l1.contracts.L1GraphTokenGateway
    const l1StartBlock = taskArgs.l1StartBlock ? parseInt(taskArgs.l1StartBlock) : 0
    const l2StartBlock = taskArgs.l2StartBlock ? parseInt(taskArgs.l2StartBlock) : 0
    const l2EndBlock = taskArgs.l2EndBlock ? parseInt(taskArgs.l2EndBlock) : 'latest'

    console.log(
      `Tracking 'WithdrawalInitiated' events on L2GraphTokenGateway (${l2Gateway.address}) from block ${l2StartBlock} to block ${l2EndBlock}`,
    )
    console.log(
      `Tracking 'WithdrawalFinalized' events on L1GraphTokenGateway (${l1Gateway.address}) from block ${l1StartBlock} onwards`,
    )

    let totalGRTClaimed = ethers.BigNumber.from(0)
    let totalGRTConfirmed = ethers.BigNumber.from(0)
    let totalGRTUnconfirmed = ethers.BigNumber.from(0)

    const withdrawalFinalizedEvents = await Promise.all(
      (
        await l1Gateway.queryFilter(l1Gateway.filters.WithdrawalFinalized(), l1StartBlock)
      ).map(async (e) => {
        const receipt = await e.getTransactionReceipt()
        const outBoxTransactionExecutedEvent = receipt.logs.find(
          (log) =>
            log.topics[0] ===
            keccak256(
              ethers.utils.toUtf8Bytes(
                'OutBoxTransactionExecuted(address,address,uint256,uint256)',
              ),
            ),
        )

        return {
          blockNumber: e.blockNumber,
          transactionHash: e.transactionHash,
          transactionIndex: outBoxTransactionExecutedEvent
            ? BigNumber.from(outBoxTransactionExecutedEvent.data)
            : null,
        }
      }),
    )

    const withdrawalInitiatedEvents = await Promise.all(
      (
        await l2Gateway.queryFilter(
          l2Gateway.filters.WithdrawalInitiated(),
          l2StartBlock,
          l2EndBlock,
        )
      ).map(async (e) => {
        const status = await getL2ToL1MessageStatus(
          e.transactionHash,
          graph.l1.provider,
          graph.l2.provider,
        )
        if (status === L2ToL1MessageStatus.EXECUTED)
          totalGRTClaimed = totalGRTClaimed.add(e.args.amount)
        if (status === L2ToL1MessageStatus.CONFIRMED)
          totalGRTConfirmed = totalGRTConfirmed.add(e.args.amount)
        if (status === L2ToL1MessageStatus.UNCONFIRMED)
          totalGRTUnconfirmed = totalGRTUnconfirmed.add(e.args.amount)

        // Find L1 event
        const l1Event = withdrawalFinalizedEvents.find((ev) =>
          ev.transactionIndex.eq(e.args.l2ToL1Id),
        )

        return {
          l2Tx: `Block ${e.blockNumber} (${new Date(
            (await graph.l2.provider.getBlock(e.blockNumber)).timestamp * 1000,
          ).toLocaleString()}) ${e.transactionHash}`,
          l1Tx: l1Event
            ? `Block ${l1Event.blockNumber} (${new Date(
                (await graph.l1.provider.getBlock(l1Event.blockNumber)).timestamp * 1000,
              ).toLocaleString()}) ${l1Event.transactionHash}`
            : '-',
          amount: prettyBigNumber(e.args.amount),
          status: emojifyL2ToL1Status(status),
        }
      }),
    )

    console.log(
      `\nFound ${withdrawalInitiatedEvents.length} withdrawals for a total of ${prettyBigNumber(
        totalGRTClaimed.add(totalGRTConfirmed).add(totalGRTUnconfirmed),
      )} GRT`,
    )
    console.log(`- Total GRT claimed on L1 (executed): ${prettyBigNumber(totalGRTClaimed)} GRT`)
    console.log(
      `- Total GRT claimable on L1 (confirmed): ${prettyBigNumber(totalGRTConfirmed)} GRT`,
    )
    console.log(`- Total GRT on transit (unconfirmed): ${prettyBigNumber(totalGRTUnconfirmed)} GRT`)

    console.log(
      '\nL2 to L1 message status reference: 🚧 = unconfirmed, ⚠️  = confirmed, ✅ = executed',
    )

    printEvents(withdrawalInitiatedEvents)
    console.timeEnd('runtime')
    console.timeLog('runtime')
  })

function printEvents(events: any[]) {
  const tablePrinter = new Table({
    charLength: { '🚧': 2, '✅': 2, '⚠️': 1, '❌': 2 },
    columns: [
      { name: 'status', color: 'green', alignment: 'center' },
      { name: 'l2Tx', color: 'green', alignment: 'center', maxLen: 72, title: 'L2 transaction' },
      { name: 'l1Tx', color: 'green', alignment: 'center', maxLen: 72, title: 'L1 transaction' },
      { name: 'amount', color: 'green' },
    ],
  })

  events.map((e) => {
    tablePrinter.addRow(e)
    tablePrinter.addRow({}) // For table padding
  })
  tablePrinter.printTable()
}

function emojifyL2ToL1Status(status: L2ToL1MessageStatus): string {
  switch (status) {
    case L2ToL1MessageStatus.UNCONFIRMED:
      return '🚧'
    case L2ToL1MessageStatus.CONFIRMED:
      return '⚠️ '
    case L2ToL1MessageStatus.EXECUTED:
      return '✅'
    default:
      return '❌'
  }
}

// Format BigNumber to 2 decimal places
function prettyBigNumber(amount: ethers.BigNumber): string {
  return (+ethers.utils.formatEther(amount)).toFixed(2)
}
