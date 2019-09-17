import * as fs from 'fs'
import * as path from 'path'
import { ethers, utils, Wallet } from 'ethers'
import * as ipfsHttpClient from 'ipfs-http-client'
import * as bs58 from 'bs58'

import { GNSFactory } from '../build/typechain/contracts/GNSFactory'
import { StakingFactory } from '../build/typechain/contracts/StakingFactory'
import { ServiceRegistryFactory } from '../build/typechain/contracts/ServiceRegistryFactory'
import { GraphTokenFactory } from '../build/typechain/contracts/GraphTokenFactory'

let addresses = (JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', 'addresses.json'), 'utf-8'),
) as any).ropsten
let privateKey = fs
  .readFileSync(path.join(__dirname, '..', '.privkey.txt'), 'utf-8')
  .trim()
let infuraKey = fs
  .readFileSync(path.join(__dirname, '..', '.infurakey.txt'), 'utf-8')
  .trim()

let ethereum = `https://ropsten.infura.io/v3/${infuraKey}`
let eth = new ethers.providers.JsonRpcProvider(ethereum)
let wallet = Wallet.fromMnemonic(privateKey)
wallet = wallet.connect(eth)

export const contracts = {
  gns: GNSFactory.connect(addresses.GNS, wallet),
  staking: StakingFactory.connect(addresses.Staking, wallet),
  serviceRegistry: ServiceRegistryFactory.connect(addresses.ServiceRegistry, wallet),
  graphToken: GraphTokenFactory.connect(addresses.GraphToken, wallet),
}

export const createIpfsClient = (node: string) => {
  let url: URL
  try {
    url = new URL(node)
  } catch (e) {
    throw new Error(
      `Invalid IPFS URL: ${node}. ` +
        `The URL must be of the following format: http(s)://host[:port]/[path]`,
    )
  }

  return ipfsHttpClient({
    protocol: url.protocol.replace(/[:]+$/, ''),
    host: url.hostname,
    port: url.port,
    'api-path': url.pathname.replace(/\/$/, '') + '/api/v0/',
  })
}

export const ipfsHashToBytes32 = (hash: string) => bs58.decode(hash).slice(2)

export const subgraphNameToDomainHash = (subgraphName: string) =>
  utils.solidityKeccak256(
    ['bytes', 'bytes'],
    [
      utils.solidityKeccak256(['string'], [subgraphName.split('/')[1]]),
      utils.solidityKeccak256(['string'], [subgraphName.split('/')[0]]),
    ],
  )
