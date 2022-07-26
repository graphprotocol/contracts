import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../cli/config'

describe('GraphToken deployment', () => {
  const {
    graphConfig,
    contracts: { GraphToken, RewardsManager },
    getDeployer,
  } = hre.graph()

  it('should be owned by governor', async function () {
    const owner = await GraphToken.governor()
    const governorAddress = getItemValue(graphConfig, 'general/governor')
    expect(owner).eq(governorAddress)
  })

  it('deployer should not be minter', async function () {
    const deployer = await getDeployer()
    const deployerIsMinter = await GraphToken.isMinter(deployer.address)
    hre.network.config.chainId === 1337 ? this.skip() : expect(deployerIsMinter).eq(false)
  })

  it('RewardsManager should be minter', async function () {
    const deployerIsMinter = await GraphToken.isMinter(RewardsManager.address)
    expect(deployerIsMinter).eq(true)
  })

  it('total supply should match "initialSupply" on the config file', async function () {
    const value = await GraphToken.totalSupply()
    const expected = getItemValue(graphConfig, 'contracts/GraphToken/init/initialSupply')
    hre.network.config.chainId === 1337 ? expect(value).eq(expected) : expect(value).gte(expected)
  })
})
