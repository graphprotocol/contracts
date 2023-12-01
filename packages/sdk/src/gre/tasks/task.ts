import { task } from 'hardhat/config'
import { ActionType, ConfigurableTaskDefinition } from 'hardhat/types/runtime'

export function graphTask(
  name: string,
  description?: string,
  action?: ActionType<unknown>,
): ConfigurableTaskDefinition {
  return task(name, description, action)
    .addOptionalParam('addressBook', 'Path to the address book file.')
    .addOptionalParam(
      'graphConfig',
      'Path to the graph config file for the network specified using --network.',
    )
    .addOptionalParam('l1GraphConfig', 'Path to the graph config file for the L1 network.')
    .addOptionalParam('l2GraphConfig', 'Path to the graph config file for the L2 network.')
    .addFlag('disableSecureAccounts', 'Disable secure accounts.')
}
