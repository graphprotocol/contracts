import { configureL1Bridge, configureL2Bridge, setPausedBridge } from '@graphprotocol/sdk'
import { greTask } from '@graphprotocol/sdk/gre'

greTask('migrate:bridge', 'Configure and unpause bridge')
  .addOptionalParam(
    'arbitrumAddressBook',
    'The path to the address book file for Arbitrum deployments',
    './arbitrum-addresses.json',
  )
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  .setAction(async (taskArgs: any, hre: any) => {
    const graph = hre.graph(taskArgs)

    if (!graph.l1) {
      throw new Error('L1 network not available')
    }
    if (!graph.l2) {
      throw new Error('L2 network not available')
    }

    const { governor: l1Governor } = await graph.l1.getNamedAccounts()
    const { governor: l2Governor } = await graph.l2.getNamedAccounts()

    await configureL1Bridge(graph.l1.contracts, l1Governor, {
      l2GRTAddress: graph.l2.contracts.GraphToken.address,
      l2GRTGatewayAddress: graph.l2.contracts.L2GraphTokenGateway?.address || '',
      l2GNSAddress: graph.l2.contracts.L2GNS?.address || '',
      l2StakingAddress: graph.l2.contracts.L2Staking?.address || '',
      arbAddressBookPath: taskArgs.arbitrumAddressBook,
      chainId: graph.l1.chainId,
    })

    await configureL2Bridge(graph.l2.contracts, l2Governor, {
      l1GRTAddress: graph.l1.contracts.GraphToken.address,
      l1GRTGatewayAddress: graph.l1.contracts.L1GraphTokenGateway?.address || '',
      l1GNSAddress: graph.l1.contracts.L1GNS?.address || '',
      l1StakingAddress: graph.l1.contracts.L1Staking?.address || '',
      arbAddressBookPath: taskArgs.arbitrumAddressBook,
      chainId: graph.l2.chainId,
    })

    await setPausedBridge(graph.l1.contracts, l1Governor, { paused: false })
    await setPausedBridge(graph.l2.contracts, l2Governor, { paused: false })

    console.log('Done!')
  })
