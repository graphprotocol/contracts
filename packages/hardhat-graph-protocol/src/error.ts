import { HardhatPluginError } from 'hardhat/plugins'
import { logError } from './logger'

export class GraphPluginError extends HardhatPluginError {
  constructor(message: string) {
    super('GraphRuntimeEnvironment', message)
    logError(message)
  }
}
