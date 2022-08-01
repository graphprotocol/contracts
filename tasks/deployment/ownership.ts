import { ContractTransaction } from 'ethers'
import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'

task(
  'migrate:ownership',
  '[localhost] Accepts ownership of protocol contracts on behalf of governor',
)
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .setAction(async (taskArgs, hre) => {
    const { contracts, getNamedAccounts } = hre.graph({
      addressBook: taskArgs.addressBook,
      graphConfig: taskArgs.graphConfig,
    })
    const { governor } = await getNamedAccounts()

    console.log('> Accepting ownership of contracts')
    console.log(`- Governor: ${governor.address}`)

    const txs: ContractTransaction[] = []
    txs.push(await contracts.GraphToken.connect(governor).acceptOwnership())
    txs.push(await contracts.Controller.connect(governor).acceptOwnership())
    txs.push(await contracts.GraphProxyAdmin.connect(governor).acceptOwnership())
    txs.push(await contracts.SubgraphNFT.connect(governor).acceptOwnership())

    await Promise.all(txs.map((tx) => tx.wait()))
    console.log('Done!')
  })
