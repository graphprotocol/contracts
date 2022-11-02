import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { Contract, ContractTransaction, ethers } from 'ethers'
import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'

task('migrate:ownership', 'Accepts ownership of protocol contracts on behalf of governor')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)
    const { GraphToken, Controller, GraphProxyAdmin, SubgraphNFT } = graph.contracts
    const { governor } = await graph.getNamedAccounts()

    console.log('> Accepting ownership of contracts')
    console.log(`- Governor: ${governor.address}`)

    const governedContracts = [GraphToken, Controller, GraphProxyAdmin, SubgraphNFT]
    const txs: ContractTransaction[] = []
    for (const contract of governedContracts) {
      const tx = await acceptOwnershipIfPending(contract, governor)
      if (tx) {
        txs.push()
      }
    }

    await Promise.all(txs.map((tx) => tx.wait()))
    console.log('Done!')
  })

async function acceptOwnershipIfPending(
  contract: Contract,
  signer: SignerWithAddress,
): Promise<ContractTransaction | undefined> {
  const pendingGovernor = await contract.connect(signer).pendingGovernor()

  if (pendingGovernor === ethers.constants.AddressZero) {
    console.log(`No pending governor for ${contract.address}`)
    return
  }

  if (pendingGovernor === signer.address) {
    console.log(`Accepting ownership of ${contract.address}`)
    return contract.connect(signer).acceptOwnership()
  } else {
    console.log(
      `Signer ${signer.address} is not the pending governor of ${contract.address}, it is ${pendingGovernor}`,
    )
  }
}
