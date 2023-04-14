import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { ethers } from 'ethers'
import { Table } from 'console-table-printer'
import { L1ToL2MessageStatus } from '@arbitrum/sdk'
import { getL1ToL2MessageStatus } from '../../cli/arbitrum'

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
  .addOptionalParam('startBlock', 'Start block for the search')
  .addOptionalParam('endBlock', 'End block for the search')
  .setAction(async (taskArgs, hre) => {
    console.log('> L1GraphTokenGateway deposits')

    const graph = hre.graph(taskArgs)
    const gateway = graph.l1.contracts.L1GraphTokenGateway
    console.log(`Tracking 'DepositInitiated' events on ${gateway.address}`)

    const startBlock = taskArgs.startBlock ? parseInt(taskArgs.startBlock) : 0
    const endBlock = taskArgs.endBlock ? parseInt(taskArgs.endBlock) : 'latest'
    console.log(`Searching blocks from block ${startBlock} to block ${endBlock}`)

    const events = await Promise.all(
      (
        await gateway.queryFilter(gateway.filters.DepositInitiated(), startBlock, endBlock)
      ).map(async (e) => ({
        blockNumber: `${e.blockNumber} (${new Date(
          (await graph.l1.provider.getBlock(e.blockNumber)).timestamp * 1000,
        ).toLocaleString()})`,
        tx: `${e.transactionHash} ${e.args.from} -> ${e.args.to}`,
        amount: ethers.utils.formatEther(e.args.amount),
        status: emojifyRetryableStatus(
          await getL1ToL2MessageStatus(e.transactionHash, graph.l1.provider, graph.l2.provider),
        ),
      })),
    )

    const total = events.reduce(
      (acc, e) => acc.add(ethers.utils.parseEther(e.amount)),
      ethers.BigNumber.from(0),
    )
    console.log(
      `Found ${events.length} deposits with a total of ${ethers.utils.formatEther(total)} GRT`,
    )

    console.log(
      'L1 to L2 message status reference: 🚧 = not yet created, ❌ = creation failed, ⚠️  = funds deposited on L2, ✅ = redeemed, ⌛ = expired',
    )

    printEvents(events)
  })

function printEvents(events: any[]) {
  const tablePrinter = new Table({
    charLength: { '🚧': 2, '✅': 2, '⚠️': 1, '⌛': 2, '❌': 2 },
    columns: [
      { name: 'status', color: 'green', alignment: 'center' },
      { name: 'blockNumber', color: 'green', alignment: 'center' },
      {
        name: 'tx',
        color: 'green',
        alignment: 'center',
        maxLen: 88,
      },
      { name: 'amount', color: 'green', alignment: 'center' },
    ],
  })

  events.map((e) => tablePrinter.addRow(e))
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
