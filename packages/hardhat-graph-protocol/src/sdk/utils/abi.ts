// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mergeABIs(abi1: any[], abi2: any[]) {
  for (const item of abi2) {
    if (abi1.find(v => v.name === item.name) === undefined) {
      abi1.push(item)
    }
  }

  // eslint-disable-next-line @typescript-eslint/no-unsafe-return
  return abi1
}
