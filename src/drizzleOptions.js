import MultiSigWallet from './../build/contracts/MultiSigWallet.json'
import Governance from './../build/contracts/Governance.json'
import GraphToken from './../build/contracts/GraphToken.json'
import GNS from './../build/contracts/GNS.json'
import Registry from './../build/contracts/Registry.json'
import RewardManager from './../build/contracts/RewardManager.json'
import Staking from './../build/contracts/Staking.json'

const drizzleOptions = {
  web3: {
    block: false,
    fallback: {
      type: 'ws',
      url: 'ws://127.0.0.1:8545'
    }
  },
  contracts: [
    MultiSigWallet,
    Governance,
    GraphToken,
    GNS,
    Registry,
    RewardManager,
    Staking
  ],
  // events: {
  //   SimpleStorage: ['StorageSet']
  // },
  polls: {
    accounts: 1500
  }
}

export default drizzleOptions