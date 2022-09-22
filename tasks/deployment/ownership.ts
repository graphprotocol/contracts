import { ContractTransaction } from 'ethers'
import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'

task('migrate:ownership', 'Accepts ownership of protocol contracts on behalf of governor')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)
    const { GraphToken, Controller, GraphProxyAdmin, SubgraphNFT } = graph.contracts
    const { governor } = await graph.getNamedAccounts()

    console.log('> Accepting ownership of contracts')
    console.log(`- Governor: ${governor.address}`)

    const txs: ContractTransaction[] = []
    txs.push(await GraphToken.connect(governor).acceptOwnership())
    txs.push(await Controller.connect(governor).acceptOwnership())
    txs.push(await GraphProxyAdmin.connect(governor).acceptOwnership())
    txs.push(await SubgraphNFT.connect(governor).acceptOwnership())

    await Promise.all(txs.map((tx) => tx.wait()))
    console.log('Done!')
  })
