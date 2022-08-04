import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { TransactionReceipt } from '@ethersproject/abstract-provider'
import { BigNumber, BigNumberish } from 'ethers'
import { ethers } from 'hardhat'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { NetworkContracts } from '../../../cli/contracts'
import { sendTransaction } from '../../../cli/network'

export const ensureGRTAllowance = async (
  contracts: NetworkContracts,
  signer: SignerWithAddress,
  owner: string,
  spender: string,
  amount: BigNumberish,
): Promise<void> => {
  const allowance = await contracts.GraphToken.allowance(owner, spender)
  const allowTokens = BigNumber.from(amount).sub(allowance)

  if (allowTokens.gt(0)) {
    console.log(`\nApproving ${allowTokens} tokens...`)
    await sendTransaction(signer, contracts.GraphToken, 'approve', [spender, allowTokens])
  }
}

export const ensureGRTBalance = async (
  contracts: NetworkContracts,
  signer: SignerWithAddress,
  beneficiary: string,
  amount: BigNumberish,
): Promise<void> => {
  const balance = await contracts.GraphToken.balanceOf(beneficiary)
  const balanceDif = BigNumber.from(amount).sub(balance)

  if (balanceDif.gt(0)) {
    await sendTransaction(signer, contracts.GraphToken, 'transfer', [beneficiary, balanceDif])
  }
}

export const ensureETHBalance = async (
  contracts: NetworkContracts,
  signer: SignerWithAddress,
  beneficiaries: string[],
  amount: BigNumberish,
): Promise<void> => {
  const txs: Promise<TransactionReceipt>[] = []
  for (const beneficiary of beneficiaries) {
    const balance = await ethers.provider.getBalance(beneficiary)
    const balanceDif = BigNumber.from(amount).sub(balance)

    if (balanceDif.gt(0)) {
      const tx = await signer.sendTransaction({ to: beneficiary, value: balanceDif })
      txs.push(tx.wait())
    }
  }
  await Promise.all(txs)
}

// Set signers on fixture with hh signers
export const setFixtureSigners = async (
  hre: HardhatRuntimeEnvironment,
  fixture: any,
): Promise<any> => {
  const graph = hre.graph()
  const [
    indexer1,
    indexer2,
    subgraphOwner,
    curator1,
    curator2,
    curator3,
    allocation1,
    allocation2,
    allocation3,
    allocation4,
    allocation5,
    allocation6,
    allocation7,
  ] = await graph.getTestAccounts()

  fixture.indexers[0].signer = indexer1
  fixture.indexers[0].allocations[0].signer = allocation1
  fixture.indexers[0].allocations[1].signer = allocation2
  fixture.indexers[0].allocations[2].signer = allocation3

  fixture.indexers[1].signer = indexer2
  fixture.indexers[1].allocations[0].signer = allocation4
  fixture.indexers[1].allocations[1].signer = allocation5
  fixture.indexers[1].allocations[2].signer = allocation6
  fixture.indexers[1].allocations[3].signer = allocation7

  fixture.curators[0].signer = curator1
  fixture.curators[1].signer = curator2
  fixture.curators[2].signer = curator3

  fixture.subgraphOwner = subgraphOwner

  return fixture
}
