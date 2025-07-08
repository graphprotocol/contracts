interface ABIItem {
  name?: string
  [key: string]: unknown
}

export function mergeABIs(abi1: ABIItem[], abi2: ABIItem[]) {
  for (const item of abi2) {
    if (abi1.find((v) => v.name === item.name) === undefined) {
      abi1.push(item)
    }
  }
  return abi1
}
