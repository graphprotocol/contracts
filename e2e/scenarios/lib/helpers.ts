export function getGraphOptsFromArgv(): {
  graphConfig: string | undefined
  addressBook: string | undefined
} {
  const argv = process.argv.slice(2)

  const getArgv = (index: number) =>
    argv[index] && argv[index] !== 'undefined' ? argv[0] : undefined

  return {
    graphConfig: getArgv(0),
    addressBook: getArgv(1),
  }
}
