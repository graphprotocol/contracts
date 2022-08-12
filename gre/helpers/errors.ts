import { HardhatPluginError } from 'hardhat/plugins'

export class GREPluginError extends HardhatPluginError {
  constructor(message: string) {
    super('GraphRuntimeEnvironment', message)
  }
}
