import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { NetworkContracts } from '../../../cli/contracts'
import { ensureETHBalance, ensureGRTBalance } from './helpers'

export const setupAccounts = async (
  contracts: NetworkContracts,
  fixture: any,
  sender: SignerWithAddress,
): Promise<void> => {
  // Print accounts
  console.log('Setting up:')
  fixture.indexers.map((indexer, i) => console.log(`- indexer${i}: ${indexer.signer.address}`))
  console.log(`- subgraphOwner: ${fixture.subgraphOwner.address}`)
  fixture.curators.map((curator, i) => console.log(`- indexer${i}: ${curator.signer.address}`))
  console.log('\n')

  const beneficiaries: string[] = [
    ...fixture.indexers.map((i) => i.signer.address),
    fixture.subgraphOwner.address,
    ...fixture.curators.map((c) => c.signer.address),
  ]

  await ensureETHBalance(contracts, sender, beneficiaries, fixture.ethAmount)

  for (const beneficiary of beneficiaries) {
    await ensureGRTBalance(contracts, sender, beneficiary, fixture.grtAmount)
  }
}
