import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { BigNumber, providers } from 'ethers'
import PQueue from 'p-queue'
import { getActiveAllocations, getSignaledSubgraphs } from './queries'
import { deployContract, waitTransaction, toBN, toGRT } from '../../cli/network'
import { aggregate } from '../../cli/multicall'
import { chunkify } from '../../cli/helpers'
import { RewardsManager } from '../../build/types/RewardsManager'
import { deriveChannelKey } from '../../test/lib/testHelpers'

const { ethers } = hre

const L1_BRIDGE_ADDRESS = '0xaf4159A80B6Cc41ED517DB1c453d1Ef5C2e4dB72'
const L1_OUTBOX_ADDRESS = '0x45Af9Ed1D03703e480CE7d328fB684bb67DA5049'
const OUTBOX_BYTECODE =
  '0x608060405234801561001057600080fd5b5060ef8061001f6000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c806380648b0214602d575b600080fd5b60336047565b604051603e919060a0565b60405180910390f35b600073ef2757855d2802ba53733901f90c91645973f743905090565b600073ffffffffffffffffffffffffffffffffffffffff82169050919050565b6000608c826063565b9050919050565b609a816083565b82525050565b600060208201905060b360008301846093565b9291505056fea2646970667358221220b9864f80758fd3804691a2c18de469ed91a0aa7a07d8677145b484e97af6770564736f6c63430008120033'
const BRIDGE_BYTECODE =
  '0x608060405234801561001057600080fd5b5060ef8061001f6000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c8063ab5d894314602d575b600080fd5b60336047565b604051603e919060a0565b60405180910390f35b60007345af9ed1d03703e480ce7d328fb684bb67da5049905090565b600073ffffffffffffffffffffffffffffffffffffffff82169050919050565b6000608c826063565b9050919050565b609a816083565b82525050565b600060208201905060b360008301846093565b9291505056fea26469706673582212200bb48ca931ae7d65d77d7724b2df13bd6c0f1a09102ea0a81f9d79e7fe677dea64736f6c63430008120033'

async function main() {
  // TODO: make read address.json with override chain id
  const { contracts, provider, getDeployer } = hre.graph({
    addressBook: 'addresses.json',
    // graphConfig: 'config/graph.mainnet.yml',
    graphConfig: 'config/graph.goerli.yml',
  })

  console.log('>>>>>>>>>>>>>>', contracts.L1GraphTokenGateway.address)

  // setup roles
  //   const l1Bridge = await ethers.getImpersonatedSigner(L1_BRIDGE_ADDRESS)
  //   const l1Bridge = ethers.getSigner(L1_BRIDGE_ADDRESS)
  await provider.send('anvil_impersonateAccount', [L1_BRIDGE_ADDRESS])
  const l1Bridge = provider.getSigner(L1_BRIDGE_ADDRESS)

  //
  await provider.send('anvil_setCode', [L1_OUTBOX_ADDRESS, OUTBOX_BYTECODE])
  await provider.send('anvil_setCode', [L1_BRIDGE_ADDRESS, BRIDGE_BYTECODE])

  const hackerAddress = '0x8a0e5c8f2c9b1b9b2b0b0b0b0b0b0b0b0b0b0b0b'

  //   const data = await contracts.L1GraphTokenGateway.connect(
  //     l1Bridge,
  //   ).populateTransaction.finalizeInboundTransfer(
  //     contracts.GraphToken.address,
  //     hackerAddress,
  //     hackerAddress,
  //     toGRT('1'),
  //     '0x',
  //   )
  //   console.log(data)

  const deployer = await getDeployer()
  await contracts.GraphToken.connect(deployer).transfer(
    contracts.L1GraphTokenGateway.address,
    toGRT('1'),
  )

  //   const tx = await contracts.L1GraphTokenGateway.connect(l1Bridge).finalizeInboundTransfer(
  //     contracts.GraphToken.address,
  //     hackerAddress,
  //     hackerAddress,
  //     toGRT('1000000000000000'),
  //     '0x',
  //   )
  //   console.log('txxxxxx', tx.hash)
  //   const rx = await tx.wait()
  //   console.log(rx.transactionHash)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
