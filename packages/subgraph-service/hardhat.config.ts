import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  solidity: '0.8.25',
  paths: {
    artifacts: './build/contracts',
  },
}

export default config
