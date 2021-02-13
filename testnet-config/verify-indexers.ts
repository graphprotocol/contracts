import fs from 'fs'
import { utils } from 'ethers'

// TODO - send out some email about the invalid addresses? or don't bother?

const parseAddresses = (): string[] => {
  const rawAddrs = fs.readFileSync(__dirname + '/airtable-raw.csv', 'utf-8')
  const addrs = rawAddrs.split('\n').map((a) => a.trim())
  const lowercaseAddrs = addrs.map((a) => a.toLocaleLowerCase())
  return lowercaseAddrs
}

const verifyAddresses = (addresses: string[]): string[] => {
  const verifiedAddresses: string[] = []
  for (const address of addresses) {
    if (utils.isAddress(address)) {
      verifiedAddresses.push(address)
    } //else {
    //   console.log(`Address is not valid: ${address}`)
    // }
  }
  return verifiedAddresses
}

const dedupe = (addresses: string[]): string[] => {
  const uniqueSet = new Set(addresses)
  return [...uniqueSet]
}

const addNewToIndexerList = (addresses: string[]): void => {
  const oldIndexersRaw = fs.readFileSync(__dirname + '/indexer-list.csv', 'utf-8')
  const oldIndexers = oldIndexersRaw.split('\n').map((oi) => oi.split(',').shift())

  let newAddrCounter = 0

  addresses.forEach((a) => {
    const exists = oldIndexers.indexOf(a) !== -1
    if (!exists) {
      fs.writeFileSync(__dirname + '/indexer-list.csv', `\n${a},1000000,false`, {
        flag: 'a+',
      })
      newAddrCounter++
    }
  })

  console.log(`${newAddrCounter} indexers added to the list`)
}

const main = (): void => {
  const parsed = parseAddresses()
  const verified = verifyAddresses(parsed)
  const deduped = dedupe(verified)
  console.log(`${parsed.length} total addresses from airtable`)
  console.log(`${parsed.length - verified.length} invalid addresses removed`)
  console.log(`${verified.length - deduped.length} addresses deduped`)
  addNewToIndexerList(deduped)
}

main()
