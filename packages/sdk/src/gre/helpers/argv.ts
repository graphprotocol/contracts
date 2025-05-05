import { GraphRuntimeEnvironmentOptions } from '../types'

export function getGREOptsFromArgv(): GraphRuntimeEnvironmentOptions {
  const argv = process.argv.slice(2)

  const getArgv: any = (index: number) =>
    argv[index] && argv[index] !== 'undefined' ? argv[index] : undefined

  return {
    addressBook: getArgv(0),
    graphConfig: getArgv(1),
    l1GraphConfig: getArgv(2),
    l2GraphConfig: getArgv(3),
    disableSecureAccounts: getArgv(4) === 'true',
    fork: getArgv(5) === 'true',
  }
}
