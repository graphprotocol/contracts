import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../cli/config'

describe('GraphToken deployment', () => {
  const {
    graphConfig,
    contracts: { GraphToken, RewardsManager, Controller },
  } = hre.graph()

  let deployer: SignerWithAddress

  before(async () => {
    ;[deployer] = await hre.ethers.getSigners()
  })

  it('should be owned by governor', async function () {
    const owner = await GraphToken.governor()
    const governorAddress = getItemValue(graphConfig, 'general/governor')
    expect(owner).eq(governorAddress)
  })

  it('deployer should not be minter', async function () {
    const deployerIsMinter = await GraphToken.isMinter(deployer.address)
    expect(deployerIsMinter).eq(false)
  })

  it('RewardsManager should be minter', async function () {
    const deployerIsMinter = await GraphToken.isMinter(RewardsManager.address)
    expect(deployerIsMinter).eq(true)
  })

  it('total supply should match "initialSupply" on the config file', async function () {
    const value = await GraphToken.totalSupply()
    const expected = getItemValue(graphConfig, 'contracts/GraphToken/init/initialSupply')
    expect(value).eq(expected)
  })
})
