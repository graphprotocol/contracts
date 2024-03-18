import fs from 'fs'
import { task } from 'hardhat/config'

function saveProxyAddresses(data) {
  try {
    fs.writeFileSync('.proxies.json', JSON.stringify(data, null, 2))
  } catch (e) {
    console.log(`Error saving artifacts: ${e.message}`)
  }
}

interface UpgradeableContract {
  name: string
  libraries?: string[]
}

const UPGRADEABLE_CONTRACTS: UpgradeableContract[] = [
  { name: 'EpochManager' },
  { name: 'Curation' },
  { name: 'Staking', libraries: ['LibExponential'] },
  { name: 'DisputeManager' },
  { name: 'RewardsManager' },
  { name: 'ServiceRegistry' },
]

task('test:upgrade-setup', 'Deploy contracts using an OZ proxy').setAction(
  async (_, hre) => {
    const contractAddresses = {}
    for (const upgradeableContract of UPGRADEABLE_CONTRACTS) {
      // Deploy libraries
      const deployedLibraries = {}
      if (upgradeableContract.libraries) {
        for (const libraryName of upgradeableContract.libraries) {
          const libraryFactory = await hre.ethers.getContractFactory(libraryName)
          const libraryInstance = await libraryFactory.deploy()
          deployedLibraries[libraryName] = libraryInstance.address
        }
      }

      // Deploy contract with Proxy
      const contractFactory = await hre.ethers.getContractFactory(upgradeableContract.name, {
        libraries: deployedLibraries,
      })
      const deployedContract = await hre.upgrades.deployProxy(contractFactory, {
        initializer: false,
        unsafeAllowLinkedLibraries: true,
      })
      contractAddresses[upgradeableContract.name] = deployedContract.address
    }

    // Save proxies to a file
    saveProxyAddresses(contractAddresses)
  },
)
