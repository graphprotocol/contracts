import { ContractTransaction } from 'ethers'
import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { GraphNetworkContractName, acceptOwnership } from '@graphprotocol/sdk'

task('migrate:ownership', 'Accepts ownership of protocol contracts on behalf of governor')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)
    const { governor } = await graph.getNamedAccounts()

    console.log('> Accepting ownership of contracts')
    console.log(`- Governor: ${governor.address}`)

    const governedContracts: GraphNetworkContractName[] = [
      'GraphToken',
      'Controller',
      'GraphProxyAdmin',
      'SubgraphNFT',
    ]
    const txs: ContractTransaction[] = []
    for (const contract of governedContracts) {
      const tx = await acceptOwnership(graph.contracts, governor, { contractName: contract })
      if (tx) {
        txs.push()
      }
    }

    await Promise.all(txs.map((tx) => tx.wait()))
    console.log('Done!')
  })
