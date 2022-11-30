import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { ethers } from 'ethers'
import { Table } from 'console-table-printer'

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
    console.log(`Searching blocks from ${startBlock} to ${endBlock}`)

    const events = (
      await gateway.queryFilter(gateway.filters.DepositInitiated(), startBlock, endBlock)
    ).map((e) => ({
      blockNumber: e.blockNumber,
      transactionHash: e.transactionHash,
      from: e.args.from,
      to: e.args.to,
      amount: ethers.utils.formatEther(e.args.amount),
    }))

    printEvents(events)
  })

function printEvents(events: any[]) {
  const tablePrinter = new Table({
    columns: [
      { name: 'blockNumber', color: 'green' },
      {
        name: 'transactionHash',
        color: 'green',
      },
      { name: 'from', color: 'green' },
      { name: 'to', color: 'green' },
      { name: 'amount', color: 'green' },
    ],
  })

  events.map((e) => tablePrinter.addRow(e))
  tablePrinter.printTable()
}
