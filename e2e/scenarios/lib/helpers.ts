export function getGraphOptsFromArgv(): {
  graphConfig: string | undefined
  addressBook: string | undefined
  disableSecureAccounts?: boolean | undefined
} {
  const argv = process.argv.slice(2)

  const getArgv: any = (index: number) =>
    argv[index] && argv[index] !== 'undefined' ? argv[index] : undefined

  return {
    graphConfig: getArgv(0),
    addressBook: getArgv(1),
    disableSecureAccounts: getArgv(2),
  }
}
