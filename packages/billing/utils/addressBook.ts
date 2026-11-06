import fs from 'fs'

export const getAddressBook = (path: string, chainId: string): any => {
  if (!path) throw new Error(`A path to the address book file is required.`)
  if (!chainId) throw new Error(`A chainId is required.`)

  const addressBook = JSON.parse(fs.readFileSync(path, 'utf8') || '{}')

  if (!addressBook[chainId]) {
    addressBook[chainId] = {}
  }

  return addressBook
}
