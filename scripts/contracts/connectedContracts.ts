import * as fs from 'fs'
import { Wallet, BigNumberish, utils, ContractTransaction, Contract } from 'ethers'

// Contract factories
import { CurationFactory } from '../../build/typechain/contracts/CurationContract'
import { GnsFactory } from '../../build/typechain/contracts/GnsContract'
import { ServiceRegistryFactory } from '../../build/typechain/contracts/ServiceRegistryContract'
import { StakingFactory } from '../../build/typechain/contracts/StakingContract'
import { GraphTokenFactory } from '../../build/typechain/contracts/GraphTokenContract'
import { IEthereumDidRegistryFactory } from '../../build/typechain/contracts/IEthereumDidRegistryContract'

import { getNetworkAddresses, IPFS } from './helpers'
import { connectContracts } from './connectedNetwork'
import {
  SubgraphMetadata,
  AccountMetadata,
  jsonToAccountMetadata,
  jsonToSubgraphMetadata,
} from '../metadataHelpers'

/**** connectedContracts.ts Description
 * Connect to individual contracts that wrap the typescript bindings, and add in extra functionality
 * to make these one call functions more easily used in CLIs and the front end. For example:
 *  - taking a JSON file for metadata, handling it, and uploading it to IPFS,
 *  - applying BN to numbers
 *  - applying overrides, with estimates
 *  - and more
 *  */

/**
 * @dev ConnectedContract
 * @gasPrice Pass a gas price to be used for all functions. Useful tie in for metamask when network is
 * at a high price. TODO - tie into ethgasstation.io api
 * @gasLimit Pass a gas limit to be used for all functions, in case auto estimate by ethers isnt working
 * @wallet Pass a wallet in, which will become the signer. If no wallet is passed, it defaults to
 * the mnemonic in .env. This allows it to be used in CLI and front end.
 * @network Pass in the network for the contract to be connected to. Defaults to the current network
 * we are using for testing (i.e. kovan, next rinkeby)
 * @note Connect to addresses in addresses.json for the chosen network
 */
class ConnectedContract {
  constructor(
    readonly network: string,
    readonly configuredWallet: Wallet,
    gasPrice?: BigNumberish,
    gasLimit?: BigNumberish,
  ) {
    this.gasPrice = gasPrice
    this.gasLimit = gasLimit
  }
  gasPrice: BigNumberish
  gasLimit: BigNumberish
  addresses = getNetworkAddresses(this.network)
  contract?: Contract
}

class ConnectedCuration extends ConnectedContract {
  contract = CurationFactory.connect(
    this.addresses.generatedAddresses.Curation.address,
    this.configuredWallet,
  )

  signalWithDecimals = async (
    deploymentID: string,
    amount: BigNumberish,
  ): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18).toString()
    return this.contract.signal(deploymentID, amountParseDecimals)
  }

  redeemWithDecimals = async (
    deploymentID: string,
    amount: BigNumberish,
  ): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18).toString()
    return this.contract.redeem(deploymentID, amountParseDecimals)
  }
}

// TODO - move away from TestRecord and use the real methods when we move to Rinkeby and mainnet
// We don't use estimate gas here, since registering ENS names won't be part of our front end
class ConnectedENS extends ConnectedContract {
  // We just lower case to normalize, but real normalization should follow:
  // https://docs.ens.domains/contract-api-reference/name-processing
  // We may not need this, as this is a convenience function,
  setTestRecord = async (name: string): Promise<ContractTransaction> => {
    const contracts = await connectContracts(this.configuredWallet, this.network)
    const normalizedName = name.toLowerCase()
    const labelNameFull = `${normalizedName}.${'test'}`
    const labelHashFull = utils.namehash(labelNameFull)
    console.log(`Namehash for ${labelNameFull}: ${labelHashFull}`)
    const signerAddress = await contracts.testRegistrar.signer.getAddress()
    const label = utils.keccak256(utils.toUtf8Bytes(normalizedName))
    return contracts.testRegistrar.register(label, signerAddress)
  }

  setText = async (name: string): Promise<ContractTransaction> => {
    const contracts = await connectContracts(this.configuredWallet, this.network)
    const normalizedName = name.toLowerCase()
    const labelNameFull = `${normalizedName}.${'test'}`
    const labelHashFull = utils.namehash(labelNameFull)
    console.log(`Setting text name: ${labelNameFull} with node: ${labelHashFull}`)
    const key = 'GRAPH NAME SERVICE'
    const signerAddress = await contracts.publicResolver.signer.getAddress()
    return contracts.publicResolver.setText(labelHashFull, key, signerAddress)
  }

  checkOwner = async (name: string): Promise<void> => {
    const contracts = await connectContracts(this.configuredWallet, this.network)
    try {
      const node = utils.namehash(`${name}.test`)
      console.log(`Node: ${node}`)
      const res = await contracts.ens.owner(node)
      console.log(`Owner of ${name}.test is: ${res}`)
    } catch (e) {
      console.log(`  ..failed on checkOwner: ${e.message}`)
    }
  }
}

class ConnectedGraphToken extends ConnectedContract {
  contract = GraphTokenFactory.connect(
    this.addresses.generatedAddresses.GraphToken.address,
    this.configuredWallet,
  )

  mintWithDecimals = async (
    account: string,
    amount: BigNumberish,
  ): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18)
    return this.contract.mint(account, amountParseDecimals)
  }

  transferWithDecimals = async (
    account: string,
    amount: BigNumberish,
  ): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18)
    return this.contract.transfer(account, amountParseDecimals)
  }

  approveWithDecimals = async (
    account: string,
    amount: BigNumberish,
  ): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18)
    return this.contract.approve(account, amountParseDecimals)
  }
}

class ConnectedEthereumDIDRegistry extends ConnectedContract {
  contract = IEthereumDidRegistryFactory.connect(
    this.addresses.permanentAddresses.ethereumDIDRegistry,
    this.configuredWallet,
  )
  pinIPFSAndSetAttribute = async (
    ipfs: string,
    pathOrData: string | AccountMetadata,
  ): Promise<ContractTransaction> => {
    const metaHashBytes = await this.handleAccountMetadata(ipfs, pathOrData)
    const signerAddress = await this.contract.signer.getAddress()
    // const name comes from: keccak256("GRAPH NAME SERVICE")
    const name = '0x72abcb436eed911d1b6046bbe645c235ec3767c842eb1005a6da9326c2347e4c'
    return this.contract.setAttribute(signerAddress, name, metaHashBytes, 0)
  }

  // Handles both a path to a JSON file, and already pre-configured AccountMetadata objects
  private handleAccountMetadata = async (
    ipfs: string,
    pathOrData: string | AccountMetadata,
  ): Promise<string> => {
    let metadata: AccountMetadata
    typeof pathOrData == 'string'
      ? (metadata = jsonToAccountMetadata(
          JSON.parse(fs.readFileSync(__dirname + pathOrData).toString()),
        ))
      : (metadata = pathOrData)
    console.log('Meta data:')
    console.log('  Code Repository: ', metadata.codeRepository || '')
    console.log('  Description:     ', metadata.description || '')
    console.log('  Image:           ', metadata.image || '')
    console.log('  Name:            ', metadata.name || '')
    console.log('  Website:         ', metadata.website || '')

    const ipfsClient = IPFS.createIpfsClient(ipfs)
    console.log('\nUpload JSON meta data to IPFS...')
    const result = await ipfsClient.add(Buffer.from(JSON.stringify(metadata)))
    const metaHash = result[0].hash
    try {
      const data = JSON.parse(await ipfsClient.cat(metaHash))
      if (JSON.stringify(data) !== JSON.stringify(metadata)) {
        throw new Error(`Original meta data and uploaded data are not identical`)
      }
    } catch (e) {
      throw new Error(`Failed to retrieve and parse JSON meta data after uploading: ${e.message}`)
    }
    console.log(`Upload metadata successful: ${metaHash}\n`)
    return IPFS.ipfsHashToBytes32(metaHash)
  }
}

class ConnectedGNS extends ConnectedContract {
  gns = GnsFactory.connect(this.addresses.generatedAddresses.GNS.address, this.configuredWallet)
  pinIPFSAndNewSubgraph = async (
    ipfs: string,
    graphAccount: string,
    subgraphDeploymentID: string,
    nameIdentifier: string,
    name: string,
    metadataPath: string | SubgraphMetadata,
  ): Promise<ContractTransaction> => {
    const metaHashBytes = await this.handleSubgraphMetadata(ipfs, metadataPath)
    const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)

    return this.gns.publishNewSubgraph(
      graphAccount,
      subgraphDeploymentIDBytes,
      nameIdentifier,
      name,
      metaHashBytes,
    )
  }

  pinIPFSAndNewVersion = async (
    ipfs: string,
    graphAccount: string,
    subgraphDeploymentID: string,
    nameIdentifier: string,
    name: string,
    metadataPath: string | SubgraphMetadata,
    subgraphNumber: string,
  ): Promise<ContractTransaction> => {
    const metaHashBytes = await this.handleSubgraphMetadata(ipfs, metadataPath)
    const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)
    return this.gns.publishNewVersion(
      graphAccount,
      subgraphNumber,
      subgraphDeploymentIDBytes,
      nameIdentifier,
      name,
      metaHashBytes,
    )
  }

  private handleSubgraphMetadata = async (
    ipfs: string,
    pathOrData: string | SubgraphMetadata,
  ): Promise<string> => {
    let metadata: SubgraphMetadata
    typeof pathOrData == 'string'
      ? (metadata = jsonToSubgraphMetadata(
          JSON.parse(fs.readFileSync(__dirname + pathOrData).toString()),
        ))
      : (metadata = pathOrData)
    console.log('Meta data:')
    console.log('  Subgraph Description:     ', metadata.subgraphDescription)
    console.log('  Subgraph Display Name:    ', metadata.subgraphDisplayName)
    console.log('  Subgraph Image:           ', metadata.subgraphImage)
    console.log('  Subgraph Code Repository: ', metadata.subgraphCodeRepository)
    console.log('  Subgraph Website:         ', metadata.subgraphWebsite)
    console.log('  Version Description:      ', metadata.versionDescription)
    console.log('  Version Label:            ', metadata.versionLabel)

    const ipfsClient = IPFS.createIpfsClient(ipfs)

    console.log('\nUpload JSON meta data to IPFS...')
    const result = await ipfsClient.add(Buffer.from(JSON.stringify(metadata)))
    const metaHash = result[0].hash
    try {
      const data = JSON.parse(await ipfsClient.cat(metaHash))
      if (JSON.stringify(data) !== JSON.stringify(metadata)) {
        throw new Error(`Original meta data and uploaded data are not identical`)
      }
    } catch (e) {
      throw new Error(`Failed to retrieve and parse JSON meta data after uploading: ${e.message}`)
    }
    console.log(`Upload metadata successful: ${metaHash}\n`)
    return IPFS.ipfsHashToBytes32(metaHash)
  }
}

class ConnectedServiceRegistry extends ConnectedContract {
  contract = ServiceRegistryFactory.connect(
    this.addresses.generatedAddresses.ServiceRegistry.address,
    this.configuredWallet,
  )
}

class ConnectedStaking extends ConnectedContract {
  contract = StakingFactory.connect(
    this.addresses.generatedAddresses.Staking.address,
    this.configuredWallet,
  )
  stakeWithDecimals = async (amount: string): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18).toString()
    return this.contract.stake(amountParseDecimals)
  }

  unstakeWithDecimals = async (amount: string): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18).toString()
    return this.contract.unstake(amountParseDecimals)
  }

  allocateWithDecimals = async (
    amount: string,
    price: string,
    channelProxy: string,
    subgraphDeploymentID: string,
    channelPubKey: string,
  ): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18).toString()
    return this.contract.allocate(
      subgraphDeploymentID,
      amountParseDecimals,
      channelPubKey,
      channelProxy,
      price,
    )
  }

  settleWithDecimals = async (amount: string): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18).toString()
    return this.contract.settle(amountParseDecimals)
  }
}

export {
  ConnectedCuration,
  ConnectedENS,
  AccountMetadata,
  ConnectedEthereumDIDRegistry,
  ConnectedGNS,
  ConnectedGraphToken,
  ConnectedServiceRegistry,
  ConnectedStaking,
}
