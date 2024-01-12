import { task } from 'hardhat/config'
import { ActionType, ConfigurableTaskDefinition } from 'hardhat/types/runtime'

function grePrefix(text: string): string {
  return `[GRE] ${text}`
}

export function greTask(
  name: string,
  description?: string | undefined,
  action?: ActionType<unknown> | undefined,
): ConfigurableTaskDefinition {
  return task(name, description, action)
    .addOptionalParam('addressBook', grePrefix('Path to the address book file.'))
    .addOptionalParam(
      'graphConfig',
      grePrefix(
        'Path to the graph config file for the network specified using --network. Lower priority than --l1GraphConfig and --l2GraphConfig.',
      ),
    )
    .addOptionalParam(
      'l1GraphConfig',
      grePrefix('Path to the graph config file for the L1 network.'),
    )
    .addOptionalParam(
      'l2GraphConfig',
      grePrefix('Path to the graph config file for the L2 network.'),
    )
    .addFlag('disableSecureAccounts', grePrefix('Disable secure accounts plugin.'))
    .addFlag('enableTxLogging', grePrefix('Enable transaction logging.'))
    .addFlag('fork', grePrefix('Wether or not the network is a fork.'))
}
