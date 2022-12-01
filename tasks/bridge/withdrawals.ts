import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { ethers } from 'ethers'
import { Table } from 'console-table-printer'

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

    const events = (
      await gateway.queryFilter(gateway.filters.WithdrawalInitiated(), startBlock, endBlock)
    ).map((e) => ({
      blockNumber: e.blockNumber,
      transactionHash: e.transactionHash,
      from: e.args.from,
      to: e.args.to,
      amount: ethers.utils.formatEther(e.args.amount),
    }))

    const total = events.reduce(
      (acc, e) => acc.add(ethers.utils.parseEther(e.amount)),
      ethers.BigNumber.from(0),
    )
    console.log(
      `Found ${events.length} withdrawals for a total of ${ethers.utils.formatEther(total)} GRT`,
    )

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
