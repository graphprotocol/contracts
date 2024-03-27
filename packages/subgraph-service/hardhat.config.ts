// import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  solidity: '0.8.24',
  paths: {
    artifacts: './build/contracts',
    sources: './contracts',
  },
}

export default config
