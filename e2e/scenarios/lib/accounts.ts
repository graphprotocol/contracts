import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber } from 'ethers'
import { ethers } from 'hardhat'
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

  // Ensure sender has enough funds to distribute
  const minEthBalance = BigNumber.from(fixture.ethAmount).mul(beneficiaries.length)
  const minGRTBalance = BigNumber.from(fixture.grtAmount).mul(beneficiaries.length)

  const senderEthBalance = await ethers.provider.getBalance(sender.address)
  const senderGRTBalance = await contracts.GraphToken.balanceOf(sender.address)

  if (senderEthBalance.lt(minEthBalance) || senderGRTBalance.lt(minGRTBalance)) {
    console.log(`Sender ETH balance: ${senderEthBalance}`)
    console.log(`Required ETH balance: ${minEthBalance}`)
    console.log(`Sender GRT balance: ${senderGRTBalance}`)
    console.log(`Required GRT balance: ${minGRTBalance}`)
    throw new Error(`Sender does not have enough funds to distribute.`)
  }

  // Fund the accounts
  await ensureETHBalance(contracts, sender, beneficiaries, fixture.ethAmount)

  for (const beneficiary of beneficiaries) {
    await ensureGRTBalance(contracts, sender, beneficiary, fixture.grtAmount)
  }
}
