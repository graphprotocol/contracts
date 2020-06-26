import * as fs from 'fs'
import { Wallet, BigNumberish, Overrides, utils, ContractTransaction, BytesLike } from 'ethers'

// Contract factories
import { CurationFactory } from '../../build/typechain/contracts/CurationContract'
import { GnsFactory } from '../../build/typechain/contracts/GnsContract'
import { ServiceRegistryFactory } from '../../build/typechain/contracts/ServiceRegistryContract'
import { StakingFactory } from '../../build/typechain/contracts/StakingContract'
import { GraphTokenFactory } from '../../build/typechain/contracts/GraphTokenContract'
import { IEthereumDidRegistryFactory } from '../../build/typechain/contracts/IEthereumDidRegistryContract'

import { getNetworkAddresses, configureWallet, IPFS } from './helpers'
import { connectContracts } from './connectedNetwork'
import {
  SubgraphMetadata,
  AccountMetadata,
  jsonToAccountMetadata,
  jsonToSubgraphMetadata,
} from '../common'
// Connect to individual contracts that wrap the typescript bindings, to make development simpler

// Passing gasPrice or gasLimit will default all txs to us this amount
// If not passed, they default to 25 and 1,000,000
// If estimate == true, all limits will be estimated by ethers.estimateGas()
// Gets network addresses from the address.json. Defaults to kovan if nothing passed
// Configures the Signer with a chosen network and mneumonic
// Defaults to kovan, and .env mnemonic if none is passed
class ConnectedContract {
  constructor(
    estimate: boolean,
    gasPrice?: BigNumberish,
    gasLimit?: BigNumberish,
    readonly wallet?: Wallet,
    readonly network?: string,
  ) {
    this.gasPrice = gasPrice
    this.gasLimit = gasLimit
    this.estimate = estimate
  }
  gasPrice: BigNumberish
  gasLimit: BigNumberish
  estimate: boolean
  addresses = getNetworkAddresses(this.network)
  configuredWallet = configureWallet(this.wallet, this.network)
}

const overrides = (gasLimit?: BigNumberish, gasPrice?: BigNumberish): Overrides => {
  if (gasPrice == undefined) gasPrice = 25
  if (gasLimit == undefined) gasLimit = 1000000
  const multiplier = 1.5 // multiplier for safety
  gasLimit = (gasLimit as number) * multiplier
  return {
    gasPrice: utils.parseUnits(gasPrice.toString(), 'gwei'),
    gasLimit: Math.floor(gasLimit),
  }
}

class ConnectedCuration extends ConnectedContract {
  curation = CurationFactory.connect(
    this.addresses.generatedAddresses.Curation.address,
    this.configuredWallet,
  )

  stakeWithOverrides = async (
    deploymentID: string,
    amount: BigNumberish,
  ): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18).toString()
    let limit
    try {
      this.estimate
        ? (limit = await this.curation.estimateGas.stake(deploymentID, amountParseDecimals))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const stakeOverrides = overrides(limit, this.gasPrice)
    return this.curation.stake(deploymentID, amountParseDecimals, stakeOverrides)
  }

  // Redeeming does not need Big Number right now
  // TODO - new contracts have decimals for shares, so this will have to be updated
  redeemWithOverrides = async (
    deploymentID: string,
    amount: BigNumberish,
  ): Promise<ContractTransaction> => {
    let limit
    try {
      this.estimate
        ? (limit = await this.curation.estimateGas.redeem(deploymentID, amount))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const redeemOverrides = overrides(limit, this.gasPrice)
    return this.curation.redeem(deploymentID, amount, redeemOverrides)
  }
}

// TODO - move away from TestRecord and use the real methods when we move to Rinkeby and mainnet
// We don't use estimate gas here - since these functions are for testing only, and will never
// be implemented elsewhere in our front end or other repositories
class ConnectedENS extends ConnectedContract {
  // Must normalize name to lower case to get script to work with ethers namehash
  // This is because in setTestRecord() - label uses the normal keccak
  // TODO - follow UTS46 in scripts https://docs.ens.domains/contract-api-reference/name-processing
  setTestRecord = async (name: string): Promise<ContractTransaction> => {
    const contracts = await connectContracts(this.configuredWallet, this.network)
    const normalizedName = name.toLowerCase()
    // const node = utils.namehash('test')
    // console.log('Namehash node for "test": ', node)
    const labelNameFull = `${normalizedName}.${'test'}`
    const labelHashFull = utils.namehash(labelNameFull)
    console.log(`Namehash for ${labelNameFull}: ${labelHashFull}`)
    const signerAddress = await contracts.testRegistrar.signer.getAddress()
    const ensOverrides = overrides()
    const label = utils.keccak256(utils.toUtf8Bytes(normalizedName))
    // console.log(`Hash of label being registered on ens ${name}: `, label)
    return contracts.testRegistrar.register(label, signerAddress, ensOverrides)
  }

  setText = async (name: string): Promise<ContractTransaction> => {
    const contracts = await connectContracts(this.configuredWallet, this.network)
    const normalizedName = name.toLowerCase()
    const labelNameFull = `${normalizedName}.${'test'}`
    const labelHashFull = utils.namehash(labelNameFull)
    console.log(`Setting text name: ${labelNameFull} with node: ${labelHashFull}`)
    const key = 'GRAPH NAME SERVICE'
    const ensOverrides = overrides()
    const signerAddress = await contracts.publicResolver.signer.getAddress()
    return contracts.publicResolver.setText(labelHashFull, key, signerAddress, ensOverrides)
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
  graphToken = GraphTokenFactory.connect(
    this.addresses.generatedAddresses.GraphToken.address,
    this.configuredWallet,
  )

  mintWithOverrides = async (
    account: string,
    amount: BigNumberish,
  ): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18)
    let limit
    try {
      this.estimate
        ? (limit = await this.graphToken.estimateGas.mint(account, amountParseDecimals))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const mintOverrides = overrides(limit, this.gasPrice)
    return this.graphToken.mint(account, amountParseDecimals, mintOverrides)
  }

  transferWithOverrides = async (
    account: string,
    amount: BigNumberish,
  ): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18)
    let limit
    try {
      this.estimate
        ? (limit = await this.graphToken.estimateGas.transfer(account, amountParseDecimals))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const transferOverrides = overrides(limit, this.gasPrice)
    return this.graphToken.transfer(account, amountParseDecimals, transferOverrides)
  }

  approveWithOverrides = async (
    account: string,
    amount: BigNumberish,
  ): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18)
    let limit
    try {
      this.estimate
        ? (limit = await this.graphToken.estimateGas.approve(account, amountParseDecimals))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const approveOverrides = overrides(limit, this.gasPrice)
    return this.graphToken.approve(account, amountParseDecimals, approveOverrides)
  }
}

class ConnectedEthereumDIDRegistry extends ConnectedContract {
  ethereumDIDRegistry = IEthereumDidRegistryFactory.connect(
    this.addresses.permanentAddresses.ethereumDIDRegistry,
    this.configuredWallet,
  )
  setAttributeWithOverrides = async (
    ipfs: string,
    pathOrData: string | AccountMetadata,
  ): Promise<ContractTransaction> => {
    const metaHashBytes = await this.handleAccountMetadata(ipfs, pathOrData)
    const signerAddress = await this.ethereumDIDRegistry.signer.getAddress()
    // name = keccak256("GRAPH NAME SERVICE")
    const name = '0x72abcb436eed911d1b6046bbe645c235ec3767c842eb1005a6da9326c2347e4c'

    let limit
    try {
      this.estimate
        ? (limit = await this.ethereumDIDRegistry.estimateGas.setAttribute(
            signerAddress,
            name,
            metaHashBytes,
            0,
          ))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const edrOverrides = overrides(limit, this.gasPrice)
    return this.ethereumDIDRegistry.setAttribute(
      signerAddress,
      name,
      metaHashBytes,
      0,
      edrOverrides,
    )
  }

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
  publishNewSubgraphWithOverrides = async (
    ipfs: string,
    graphAccount: string,
    subgraphDeploymentID: string,
    nameIdentifier: string,
    name: string,
    metadataPath: string | SubgraphMetadata,
  ): Promise<ContractTransaction> => {
    const metaHashBytes = await this.handleSubgraphMetadata(ipfs, metadataPath)
    const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)

    let limit
    try {
      this.estimate
        ? (limit = await this.gns.estimateGas.publishNewSubgraph(
            graphAccount,
            subgraphDeploymentIDBytes,
            nameIdentifier,
            name,
            metaHashBytes,
          ))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const gnsOverrides = overrides(limit, this.gasPrice)

    return this.gns.publishNewSubgraph(
      graphAccount,
      subgraphDeploymentIDBytes,
      nameIdentifier,
      name,
      metaHashBytes,
      gnsOverrides,
    )
  }

  publishNewVersionWithOverrides = async (
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

    let limit
    try {
      this.estimate
        ? (limit = await this.gns.estimateGas.publishNewSubgraph(
            graphAccount,
            subgraphDeploymentIDBytes,
            nameIdentifier,
            name,
            metaHashBytes,
          ))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const gnsOverrides = overrides(limit, this.gasPrice)

    return this.gns.publishNewVersion(
      graphAccount,
      subgraphNumber,
      subgraphDeploymentIDBytes,
      nameIdentifier,
      name,
      metaHashBytes,
      gnsOverrides,
    )
  }

  deprecateWithOverrides = async (
    graphAccount: string,
    subgraphNumber: string,
  ): Promise<ContractTransaction> => {
    let limit
    try {
      this.estimate
        ? (limit = await this.gns.estimateGas.deprecate(graphAccount, subgraphNumber))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const gnsOverrides = overrides(limit, this.gasPrice)
    return this.gns.deprecate(graphAccount, subgraphNumber, gnsOverrides)
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
  serviceRegistry = ServiceRegistryFactory.connect(
    this.addresses.generatedAddresses.ServiceRegistry.address,
    this.configuredWallet,
  )

  registerWithOverrides = async (url: string, geoHash: string): Promise<ContractTransaction> => {
    let limit
    try {
      this.estimate
        ? (limit = await this.serviceRegistry.estimateGas.register(url, geoHash))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const registerOverrides = overrides(limit, this.gasPrice)
    return this.serviceRegistry.register(url, geoHash, registerOverrides)
  }

  unRegisterWithOverrides = async (): Promise<ContractTransaction> => {
    let limit
    try {
      this.estimate
        ? (limit = await this.serviceRegistry.estimateGas.unregister())
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const unRegisterOverrides = overrides(limit, this.gasPrice)
    return this.serviceRegistry.unregister(unRegisterOverrides)
  }
}

class ConnectedStaking extends ConnectedContract {
  staking = StakingFactory.connect(
    this.addresses.generatedAddresses.Staking.address,
    this.configuredWallet,
  )
  stakeWithOverrides = async (amount: string): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18).toString()
    let limit
    try {
      this.estimate
        ? (limit = await this.staking.estimateGas.stake(amountParseDecimals))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const stakeOverrides = overrides(limit, this.gasPrice)
    return this.staking.stake(amountParseDecimals, stakeOverrides)
  }

  unstakeWithOverrides = async (amount: string): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18).toString()
    let limit
    try {
      this.estimate
        ? (limit = await this.staking.estimateGas.unstake(amountParseDecimals))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const unstakeOverrides = overrides(limit, this.gasPrice)
    return this.staking.unstake(amountParseDecimals, unstakeOverrides)
  }

  withdrawWithOverrides = async (): Promise<ContractTransaction> => {
    let limit
    try {
      this.estimate ? (limit = await this.staking.estimateGas.withdraw()) : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const withdrawOverrides = overrides(limit, this.gasPrice)
    return this.staking.staking.withdraw(withdrawOverrides)
  }

  allocateWithOverrides = async (
    amount: string,
    price: string,
    channelProxy: string,
    subgraphDeploymentID?: string,
    channelPubKey?: string,
  ): Promise<ContractTransaction> => {
    let publicKey: string
    let id: BytesLike

    subgraphDeploymentID == undefined ? (id = utils.randomBytes(32)) : (id = subgraphDeploymentID)
    channelPubKey == undefined
      ? (publicKey = Wallet.createRandom().publicKey)
      : (publicKey = channelPubKey)

    console.log(`Subgraph Deployment ID: ${id}`)
    console.log(`Channel Public Key:     ${publicKey}`)

    let limit
    try {
      this.estimate
        ? (limit = await this.staking.estimateGas.allocate(
            id,
            utils.parseUnits(amount, 18),
            publicKey,
            channelProxy,
            price,
          ))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const allocateOverrides = overrides(limit, this.gasPrice)
    return this.staking.staking.allocate(
      id,
      utils.parseUnits(amount, 18),
      publicKey,
      channelProxy,
      price,
      allocateOverrides,
    )
  }

  settleWithOverrides = async (amount: string): Promise<ContractTransaction> => {
    const amountParseDecimals = utils.parseUnits(amount as string, 18).toString()
    let limit
    try {
      this.estimate
        ? (limit = await this.staking.estimateGas.settle(amountParseDecimals))
        : (limit = this.gasLimit)
    } catch {
      console.warn('  Estimate gas failed. Using default gas limit')
      limit = this.gasLimit
    }
    const settleOverrides = overrides(limit, this.gasPrice)
    return this.staking.settle(amountParseDecimals, settleOverrides)
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
