import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { expect } from 'chai'
import { zeroPadValue } from 'ethers'
import hre from 'hardhat'
import { ethers } from 'hardhat'

const abi = [
  {
    inputs: [
      {
        internalType: 'contract ITransparentUpgradeableProxy',
        name: 'proxy',
        type: 'address',
      },
      {
        internalType: 'address',
        name: 'implementation',
        type: 'address',
      },
      {
        internalType: 'bytes',
        name: 'data',
        type: 'bytes',
      },
    ],
    name: 'upgradeAndCall',
    outputs: [],
    stateMutability: 'payable',
    type: 'function',
  },
]

describe('Upgrading contracts', () => {
  let snapshotId: string

  // Test addresses
  let governor: HardhatEthersSigner
  const graph = hre.graph()

  before(async () => {
    governor = await graph.accounts.getGovernor()
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  it('subgraph service should be upgradeable by the governor', async () => {
    const entry = graph.subgraphService.addressBook.getEntry('SubgraphService')
    const proxyAdmin = entry.proxyAdmin!
    const proxy = entry.address

    // Upgrade the contract to a different implementation
    // the implementation we use is the GraphTallyCollector, this is obviously absurd but we just need an address with code on it
    const ProxyAdmin = new ethers.Contract(proxyAdmin, abi, governor)
    await ProxyAdmin.upgradeAndCall(proxy, graph.horizon.contracts.GraphTallyCollector.target, '0x')

    // https:// github.com/OpenZeppelin/openzeppelin-contracts/blob/dbb6104ce834628e473d2173bbc9d47f81a9eec3/contracts/proxy/ERC1967/ERC1967Utils.sol#L37C53-L37C119
    const implementation = await hre.ethers.provider.getStorage(
      proxy,
      '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc',
    )
    expect(zeroPadValue(implementation, 32)).to.equal(
      zeroPadValue(graph.horizon.contracts.GraphTallyCollector.target as string, 32),
    )
  })

  it('dispute manager should be upgradeable by the governor', async () => {
    const entry = graph.subgraphService.addressBook.getEntry('DisputeManager')
    const proxyAdmin = entry.proxyAdmin!
    const proxy = entry.address

    // Upgrade the contract to a different implementation
    // the implementation we use is the GraphTallyCollector, this is obviously absurd but we just need an address with code on it
    const ProxyAdmin = new ethers.Contract(proxyAdmin, abi, governor)
    await ProxyAdmin.upgradeAndCall(proxy, graph.horizon.contracts.GraphTallyCollector.target, '0x')

    // https:// github.com/OpenZeppelin/openzeppelin-contracts/blob/dbb6104ce834628e473d2173bbc9d47f81a9eec3/contracts/proxy/ERC1967/ERC1967Utils.sol#L37C53-L37C119
    const implementation = await hre.ethers.provider.getStorage(
      proxy,
      '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc',
    )
    expect(zeroPadValue(implementation, 32)).to.equal(
      zeroPadValue(graph.horizon.contracts.GraphTallyCollector.target as string, 32),
    )
  })
})
