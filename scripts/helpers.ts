import * as fs from 'fs'
import * as path from 'path'
import * as dotenv from 'dotenv'

import { ContractTransaction, ethers, utils, Wallet, ContractReceipt, Overrides } from 'ethers'
import ipfsHttpClient from 'ipfs-http-client'
import * as bs58 from 'bs58'

import { GnsFactory } from '../build/typechain/contracts/GnsContract'
import { StakingFactory } from '../build/typechain/contracts/StakingContract'
import { ServiceRegistryFactory } from '../build/typechain/contracts/ServiceRegistryContract'
import { GraphTokenFactory } from '../build/typechain/contracts/GraphTokenContract'
import { CurationFactory } from '../build/typechain/contracts/CurationContract'
import { IensFactory } from '../build/typechain/contracts/IensContract'
import { IPublicResolverFactory } from '../build/typechain/contracts/IPublicResolverContract'
import { IEthereumDidRegistryFactory } from '../build/typechain/contracts/IEthereumDidRegistryContract'
import { ITestRegistrarFactory } from '../build/typechain/contracts/ITestRegistrarContract'

dotenv.config()
const addresses = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'addresses.json'), 'utf-8'))
const generatedAddresses = addresses['42']
const permanentAddresses = addresses.kovan // TODO - make these park of the autogen. Right now they are hardcoded

const ethereum = `https://kovan.infura.io/v3/${process.env.INFURA_KEY}`
const eth = new ethers.providers.JsonRpcProvider(ethereum)
let wallet = Wallet.fromMnemonic(process.env.MNEMONIC)
wallet = wallet.connect(eth)

export const contracts = {
  gns: GnsFactory.connect(generatedAddresses.GNS.address, wallet),
  staking: StakingFactory.connect(generatedAddresses.Staking.address, wallet),
  serviceRegistry: ServiceRegistryFactory.connect(
    generatedAddresses.ServiceRegistry.address,
    wallet,
  ),
  graphToken: GraphTokenFactory.connect(generatedAddresses.GraphToken.address, wallet),
  curation: CurationFactory.connect(generatedAddresses.Curation.address, wallet),
  ens: IensFactory.connect(permanentAddresses.ens, wallet),
  publicResolver: IPublicResolverFactory.connect(permanentAddresses.ensPublicResolver, wallet),
  ethereumDIDRegistry: IEthereumDidRegistryFactory.connect(
    permanentAddresses.ethereumDIDRegistry,
    wallet,
  ),
  testRegistrar: ITestRegistrarFactory.connect(permanentAddresses.ensTestRegistrar, wallet),
}

export const executeTransaction = async (
  transaction: Promise<ContractTransaction>,
): Promise<ContractReceipt> => {
  try {
    const tx = await transaction
    console.log(`  Transaction pending: 'https://kovan.etherscan.io/tx/${tx.hash}'`)
    const receipt = await tx.wait(1)
    console.log(`  Transaction successfully included in block #${receipt.blockNumber}`)
    return receipt
  } catch (e) {
    console.log(`  ..executeTransaction failed: ${e.message}`)
    process.exit(1)
  }
}

export const overrides = (contract: string, func: string): Overrides => {
  const gasPrice = utils.parseUnits('25', 'gwei')
  const gasLimit = 1000000
  // console.log(`\ntx gas price: '${gasPrice}'`);
  // console.log(`tx gas limit: ${gasLimit}`);

  return {
    gasPrice: gasPrice,
    gasLimit: gasLimit,
  }

  // TODO - make this unique to each function, but for now just passing 1,000,000
  // const multiplier = utils.bigNumberify(1.5)
  // switch (contract) {
  //   case 'gns':
  //     if (func == 'publish'){
  //       return {
  //         gasLimit: (await contracts.gns.estimate.publish(subgraphName, subgraphIDBytes, metaHashBytes)).mul(
  //           utils.bigNumberify(2))
  //       }
  //     }
  // }
}

export const checkFuncInputs = (
  userInputs: Array<string | undefined>,
  inputNames: Array<string>,
  functionName: string,
): void => {
  userInputs.forEach((input, i) => {
    if (input == undefined) {
      console.error(`ERROR: ${inputNames[i]} was not provided for ${functionName}()`)
      process.exit(1)
    }
  })
}

export class IPFS {
  static createIpfsClient(node: string): ipfsHttpClient {
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

  static ipfsHashToBytes32(hash: string): string {
    const hashBytes = bs58.decode(hash).slice(2)
    console.log(`base58 to bytes32: ${hash} -> ${utils.hexlify(hashBytes)}`)
    return utils.hexlify(hashBytes)
  }
}
