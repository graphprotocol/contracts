import { ContractTransaction } from 'ethers'
import { graphTask } from '../../gre/gre'

graphTask(
  'migrate:ownership',
  'Accepts ownership of protocol contracts on behalf of governor',
).setAction(async (taskArgs, hre) => {
  const { contracts, getNamedAccounts } = hre.graph(taskArgs)
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
