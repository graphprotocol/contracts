import { task } from 'hardhat/config'
import { GRE_TASK_PARAMS } from '@graphprotocol/sdk/gre'
import {
  configureL1Bridge,
  configureL2Bridge,
  isGraphL1ChainId,
  isGraphL2ChainId,
} from '@graphprotocol/sdk'

export const TASK_BRIDGE_CONFIGURE_L1 = 'bridge:configure:l1'
export const TASK_BRIDGE_CONFIGURE_L2 = 'bridge:configure:l2'

task(TASK_BRIDGE_CONFIGURE_L1, 'Configure L1 bridge')
  .addOptionalParam('addressBook', GRE_TASK_PARAMS.addressBook.description)
  .addOptionalParam(
    'arbitrumAddressBook',
    GRE_TASK_PARAMS.arbitrumAddressBook.description,
    GRE_TASK_PARAMS.arbitrumAddressBook.default,
  )
  .addOptionalParam('graphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l1GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l2GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)
    const { governor } = await graph.getNamedAccounts()

    if (isGraphL2ChainId(graph.chainId)) {
      throw new Error('Cannot set L1 configuration on an L2 network!')
    }

    await configureL1Bridge(graph.contracts, governor, {
      l2GRTAddress: graph.l2.contracts.GraphToken.address,
      l2GRTGatewayAddress: graph.l2.contracts.L2GraphTokenGateway.address,
      arbAddressBookPath: taskArgs.arbitrumAddressBook,
      chainId: graph.chainId,
    })
    console.log('Done!')
  })

task(TASK_BRIDGE_CONFIGURE_L2, 'Configure L2 bridge')
  .addOptionalParam('addressBook', GRE_TASK_PARAMS.addressBook.description)
  .addOptionalParam(
    'arbitrumAddressBook',
    GRE_TASK_PARAMS.arbitrumAddressBook.description,
    GRE_TASK_PARAMS.arbitrumAddressBook.default,
  )
  .addOptionalParam('graphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l1GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l2GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)
    const { governor } = await graph.getNamedAccounts()

    if (isGraphL1ChainId(graph.chainId)) {
      throw new Error('Cannot set L2 configuration on an L1 network!')
    }

    await configureL2Bridge(graph.contracts, governor, {
      l1GRTAddress: graph.l1.contracts.GraphToken.address,
      l1GRTGatewayAddress: graph.l1.contracts.L1GraphTokenGateway.address,
      arbAddressBookPath: taskArgs.arbitrumAddressBook,
      chainId: graph.chainId,
    })
    console.log('Done!')
  })
