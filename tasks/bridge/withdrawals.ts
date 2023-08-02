import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { ethers } from 'ethers'
import { Table } from 'console-table-printer'
import { L2ToL1MessageStatus } from '@arbitrum/sdk'
import { getL2ToL1MessageStatus } from '../../cli/arbitrum'

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
  .addOptionalParam('startBlock', 'Start block for the search')
  .addOptionalParam('endBlock', 'End block for the search')
  .setAction(async (taskArgs, hre) => {
    console.log('> L2GraphTokenGateway withdrawals')

    const graph = hre.graph(taskArgs)
    const gateway = graph.l2.contracts.L2GraphTokenGateway
    console.log(`Tracking 'WithdrawalInitiated' events on ${gateway.address}`)

    const startBlock = taskArgs.startBlock ? parseInt(taskArgs.startBlock) : 0
    const endBlock = taskArgs.endBlock ? parseInt(taskArgs.endBlock) : 'latest'
    console.log(`Searching blocks from block ${startBlock} to block ${endBlock}`)

    const events = await Promise.all(
      (
        await gateway.queryFilter(gateway.filters.WithdrawalInitiated(), startBlock, endBlock)
      ).map(async (e) => ({
        blockNumber: `${e.blockNumber} (${new Date(
          (await graph.l2.provider.getBlock(e.blockNumber)).timestamp * 1000,
        ).toLocaleString()})`,
        tx: `${e.transactionHash} ${e.args.from} -> ${e.args.to}`,
        amount: ethers.utils.formatEther(e.args.amount),
        status: emojifyL2ToL1Status(
          await getL2ToL1MessageStatus(e.transactionHash, graph.l1.provider, graph.l2.provider),
        ),
      })),
    )

    const total = events.reduce(
      (acc, e) => acc.add(ethers.utils.parseEther(e.amount)),
      ethers.BigNumber.from(0),
    )
    console.log(
      `Found ${events.length} withdrawals for a total of ${ethers.utils.formatEther(total)} GRT`,
    )

    console.log(
      'L2 to L1 message status reference: 🚧 = unconfirmed, ⚠️  = confirmed, ✅ = executed',
    )

    printEvents(events)
  })

function printEvents(events: any[]) {
  const tablePrinter = new Table({
    charLength: { '🚧': 2, '✅': 2, '⚠️': 1, '❌': 2 },
    columns: [
      { name: 'status', color: 'green', alignment: 'center' },
      { name: 'blockNumber', color: 'green' },
      {
        name: 'tx',
        color: 'green',
        alignment: 'center',
        maxLen: 88,
      },
      { name: 'amount', color: 'green' },
    ],
  })

  events.map((e) => tablePrinter.addRow(e))
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
