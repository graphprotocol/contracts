export function getGraphOptsFromArgv(): {
  addressBook: string | undefined
  graphConfig: string | undefined
  l1GraphConfig: string | undefined
  l2GraphConfig: string | undefined
} {
  const argv = process.argv.slice(2)

  const getArgv = (index: number) =>
    argv[index] && argv[index] !== 'undefined' ? argv[index] : undefined

  return {
    addressBook: getArgv(0),
    graphConfig: getArgv(1),
    l1GraphConfig: getArgv(2),
    l2GraphConfig: getArgv(3),
  }
}
