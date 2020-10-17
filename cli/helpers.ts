import fs from 'fs'
import * as dotenv from 'dotenv'
import consola from 'consola'

import { utils, providers, Wallet } from 'ethers'
import ipfsHttpClient from 'ipfs-http-client'

import * as bs58 from 'bs58'

import {
  SubgraphMetadata,
  VersionMetadata,
  jsonToSubgraphMetadata,
  jsonToVersionMetadata,
} from './metadata'

dotenv.config()

const logger = consola.create({})

export class IPFS {
  static createIpfsClient(node: string): typeof ipfsHttpClient {
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
      'api-path': url.pathname.replace(/\/$/, '') + '/api/v0/',
    })
  }

  static ipfsHashToBytes32(hash: string): string {
    const hashBytes = bs58.decode(hash).slice(2)
    return utils.hexlify(hashBytes)
  }
}

export const pinMetadataToIPFS = async (
  ipfs: string,
  type: string,
  path?: string, // Only pass path or metadata, not both
  metadata?: SubgraphMetadata | VersionMetadata,
): Promise<string> => {
  if (metadata == undefined && path != undefined) {
    if (type == 'subgraph') {
      metadata = jsonToSubgraphMetadata(JSON.parse(fs.readFileSync(__dirname + path).toString()))
      logger.log('Meta data:')
      logger.log('  Subgraph Description:     ', metadata.description)
      logger.log('  Subgraph Display Name:    ', metadata.displayName)
      logger.log('  Subgraph Image:           ', metadata.image)
      logger.log('  Subgraph Code Repository: ', metadata.codeRepository)
      logger.log('  Subgraph Website:         ', metadata.website)
    } else if (type == 'version') {
      metadata = jsonToVersionMetadata(JSON.parse(fs.readFileSync(__dirname + path).toString()))
      logger.log('Meta data:')
      logger.log('  Version Description:      ', metadata.description)
      logger.log('  Version Label:            ', metadata.label)
    }
  }

  const ipfsClient = new ipfsHttpClient(ipfs + 'api/v0')
  let result
  logger.log(`\nUpload JSON meta data for ${type} to IPFS...`)
  try {
    result = await ipfsClient.add(Buffer.from(JSON.stringify(metadata)))
  } catch (e) {
    logger.error(`Failed to upload to IPFS: ${e}`)
    return
  }

  const metaHash = result.path

  // TODO - maybe add this back in. ipfs-http-client was updated, so it broke
  // try {
  //   const data = await ipfsClient.cat(metaHash)
  //   if (JSON.stringify(data) !== JSON.stringify(metadata)) {
  //     throw new Error(`Original meta data and uploaded data are not identical`)
  //   }
  // } catch (e) {
  //   throw new Error(`Failed to retrieve and parse JSON meta data after uploading: ${e.message}`)
  // }
  logger.log(`Upload metadata successful: ${metaHash}\n`)
  return IPFS.ipfsHashToBytes32(metaHash)
}

export const mockDeploymentIDsBase58: Array<string> = [
  'Qmb7e8bYoj93F9u33R3JY1H764626C8KHUgWMeVjWPiwdD', //compound
  'QmXenxBqM7uBbRq6y7EAcy86mfcaBkWE53Tz53H3dVeeit', //used synthetix
  'QmY8Uzg61ttrogeTyCKLcDDR4gKNK44g9qkGDqeProkSHE', //ens
  'QmRkqEVeZ8bRmMfvBHJvoB4NbnPgXNcuszLZWNNF49skY8', //livepeer
  'Qmb3hd2hYd2nWFgcmRswykF1dUBSrDUrinYCgN1dmE1tNy', //maker
  'QmcqrL62BHSasBsk47tNT1G66BHbaANwY213cX841NWE61', //melon
  'QmTXzATwNfgGVukV1fX2T6xw9f6LAYRVWpsdXyRWzUR2H9', // moloch
  'QmNoMRb9c5nGi5gETeyeAc7V14XvubAMAA7sxEJzsXnpTF', //used aave
  'QmUVKS3W7G7Kog6pGq2ttZtXfE89pRvw45vEJM2YEYwpQz', //thegraph
  'QmNPKaPqgTqKdCv2k3SF9vAhbHo4PVb2cKx2Gs4PzNQkZx', //uniswap
]

export const mockDeploymentIDsBytes32: Array<string> = [
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[1]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
]

export const mockChannelPubKeys: Array<string> = [
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d50',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d51',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d52',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d54',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d55',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d56',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d57',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d58',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d59',
]

// Creates an array of wallets connected to a provider
const configureWallets = (
  mnemonic: string,
  providerEndpoint: string,
  count: number,
): Array<Wallet> => {
  const signers: Array<Wallet> = []
  for (let i = 0; i < count; i++) {
    signers.push(configureWallet(mnemonic, providerEndpoint, i.toString()))
  }
  logger.log(`Created ${count} wallets!`)
  return signers
}

const DEFAULT_MNEMONIC =
  'myth like bonus scare over problem client lizard pioneer submit female collect'
const GANACHE_ENDPOINT = 'http://localhost:8545'

export const configureGanacheWallet = (): Wallet => {
  return configureWallet(DEFAULT_MNEMONIC, GANACHE_ENDPOINT)
}

// Create a single wallet connected to a provider
export const configureWallet = (
  mnemonic: string,
  providerEndpoint: string,
  index = '0',
): Wallet => {
  if (mnemonic == undefined) {
    throw new Error(`Please set a mnemonic in a .env file at the root of the project`)
  }
  const wallet = Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${index}`)
  const eth = new providers.JsonRpcProvider(providerEndpoint)
  return wallet.connect(eth)
}

// User accounts used are always 0 to 10
export const userAccounts = (mnemonic: string, provider: string): Array<Wallet> => {
  return configureWallets(mnemonic, provider, 10)
}

/* Proxy accounts used are always 10 to 20.
    Addresses below:
    0x853d474EB22701b94910f275CdB57A62c4B2db7E
    0x2A7f74f2F90d34eceE06E6196D3da7B8FcA02fa2
    0x048CdeADbcb9E493D19b48eB7B693DC056Fd2036
    0xD03a084A951B42bEb1a30232B8f738AB288256fa
    0xEF99F3f68Dc194a3720b374c2e3AC56beF8d8D61
    0x1A8f34607F6495f7E3bF6ee7553C12602B826D7A
    0xEAaeC61E782992f85cCc096a16Fc9C74EfaA5355
    0xf7c0e78323Fcb0532cEa23d99B63C729e178568A
    0xF6cAdFc68B855e2944f27C5DF4a66c52B24d2d94
    0x4cc6B907c7Bf1480426075e832Dc35bBC7264077
*/
export const proxyAccounts = (mnemonic: string, provider: string): Array<Wallet> => {
  const wallets = configureWallets(mnemonic, provider, 20)
  return wallets.slice(10, 20)
}

/* Channel accounts used are always 20 to 30.
    Addresses below:
    0x73f0bd80493BEA09BAFAFCdc6E71A9569eAcA0aB
    0xeD12E3068Cdb1F9afD7A038c5a7B1a9b66C5986B
    0x3796d3711070222d49EE6207Fe1cd4b2fcAD0663
    0xfBD176446f56c0a52f44c5bfC24d339fF4B09470
    0xbe45140e5783c8F5fA5123fDcC74D209f3c9155b
    0x2084259748B13F800B6aE0b7A33c87e49546BfD8
    0x81A90593786e6d0fC9cF29C9842Bca4Ab2f1bEb7
    0xA3e182b8CaC70b43c84a437a4F1774447505EA40
    0x082b1536F8C9b0Ca3198a911c4934e456C2f7c32
    0xBA6D2612dEA713e61a7c22E691af4eaea46aCf75

    Uncompressed public keys below:
    0x04e8c44ab3118e5ca2e470ff20556bb6b470a5265ca0992e82e9a26cf332d87cf6e3add759bd4ed23277fadc46dd9b79fbcce33314cb4a48687830f6a524ebb998
    0x04c10f828e7ee0cc03dfed95bb8497de9d5366c6b13d9524ef8bcabdd5b1f58f1a38de3332e16a124da62ac298ed1cbfc6d867576635a0151c55ac3d9c84778f1c
    0x04d51dc84783a733fbe1ab91255d8fcd0195c8a03937dd6791426142de8e8da6eb5519cab9730648e3c3dac51bc0865347d80860b7c707944a051e0896cbc7b632
    0x04dc700c3efcb80c151de25ae5ffa417f2556b5b3a0c9edba771febfdd9f8ea82943f62709942ea23185771b96c976cbb709e307130b4ea343b1888ef200166cce
    0x04185736d5509a687f0b64dd5caf4497443650d67708138daff1ccf3aa900d936cd399a25a58951f3801dfb61f81d48b396e49296bcac67ca35aed5e65fd5e65ed
    0x04f4fd3d15f633540db5fd5f69f3a83b5f9a43b258c0855e8f87dd586e9fd33fb06d72fbfad9fd90c1fd59eccf6589099403583cfb89604eb1b0eb472e61f5fefe
    0x04a880416006af0996a76e1b5d6171c005009d55bd7af8ed78b2af6bfbfafdff755c68f0e32e49ca0627acceec1611d5521dde7b90076c4ba1894e3dfb53c01ffd
    0x047da2b532a32e1f87b570a4675e71fa9a794c43cda4562d1e9c55975534b335f00c8ac1006b7b303d4e72189af7caa70112eff9b47bfe00e37b4d832fcc716b50
    0x04cc3c74d466211b119217e97806f8ec5f09d865940c99effaae967dc67e282ff09aa1900fdb14865f8e3323cac75d6f193fa85b5c732b742163d1d83d699c04a3
    0x04c9558bb809ed4c65cce849db4337c29b6c72bec97bb6a600a8af7fc72ded8486ae3a76916e424c9cef6e40721f9c8b265056862897afad7cc859b8e34d4dbc95
*/
export const channelAccounts = (mnemonic: string, provider: string): Array<Wallet> => {
  const wallets = configureWallets(mnemonic, provider, 30)
  return wallets.slice(20, 30)
}
