import { HardhatPluginError } from 'hardhat/plugins'
import { logError } from './logger'

export class GREPluginError extends HardhatPluginError {
  constructor(message: string) {
    super('GraphRuntimeEnvironment', message)
    logError(message)
  }
}
