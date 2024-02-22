import { utils } from 'ethers'
import consola from 'consola'

import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const { parseEther } = utils

const logger = consola.create({})

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments
  const { deployer } = await hre.getNamedAccounts()

  // -- Fake Graph Token --

  logger.info('Deploying GraphTokenMock...')

  await deploy('GraphTokenMock', {
    from: deployer,
    args: [
      parseEther('10000000000'), // 10B
      deployer,
    ],
    log: true,
  })
}

func.skip = (hre: HardhatRuntimeEnvironment) => Promise.resolve(hre.network.name === 'mainnet')
func.tags = ['test']

export default func
