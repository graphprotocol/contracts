import {
  getAccounts as getAccountsToolshed,
  getArbitrator,
  getDeployer,
  getGateway, getGovernor, getPauseGuardian, getSubgraphAvailabilityOracle, getTestAccounts,
  TEN_MILLION,
} from '@graphprotocol/toolshed'
import { setGRTBalance } from '@graphprotocol/toolshed/hardhat'

import type { Addressable } from 'ethers'
import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

type Accounts = {
  getAccounts: () => ReturnType<typeof getAccountsToolshed>
  getDeployer: (accountIndex?: number) => ReturnType<typeof getDeployer>
  getGovernor: (accountIndex?: number) => ReturnType<typeof getGovernor>
  getArbitrator: (accountIndex?: number) => ReturnType<typeof getArbitrator>
  getPauseGuardian: (accountIndex?: number) => ReturnType<typeof getPauseGuardian>
  getSubgraphAvailabilityOracle: (accountIndex?: number) => ReturnType<typeof getSubgraphAvailabilityOracle>
  getGateway: (accountIndex?: number) => ReturnType<typeof getGateway>
  getTestAccounts: () => ReturnType<typeof getTestAccounts>
}

export function getAccounts(provider: HardhatEthersProvider, chainId: number, grtTokenAddress: string | Addressable | undefined): Accounts {
  return {
    getAccounts: async () => {
      const accounts = await getAccountsToolshed(provider)
      for (const account of Object.values(accounts)) {
        if (typeof account === 'object' && 'address' in account) {
          await setBalanceIfLocal(provider, chainId, grtTokenAddress, account)
        } else if (Array.isArray(account)) {
          for (const testAccount of account) {
            await setBalanceIfLocal(provider, chainId, grtTokenAddress, testAccount)
          }
        }
      }
      return accounts
    },
    getDeployer: async (accountIndex?: number) => {
      const account = await getDeployer(provider, accountIndex)
      await setBalanceIfLocal(provider, chainId, grtTokenAddress, account)
      return account
    },
    getGovernor: async (accountIndex?: number) => {
      const account = await getGovernor(provider, accountIndex)
      await setBalanceIfLocal(provider, chainId, grtTokenAddress, account)
      return account
    },
    getArbitrator: async (accountIndex?: number) => {
      const account = await getArbitrator(provider, accountIndex)
      await setBalanceIfLocal(provider, chainId, grtTokenAddress, account)
      return account
    },
    getPauseGuardian: async (accountIndex?: number) => {
      const account = await getPauseGuardian(provider, accountIndex)
      await setBalanceIfLocal(provider, chainId, grtTokenAddress, account)
      return account
    },
    getSubgraphAvailabilityOracle: async (accountIndex?: number) => {
      const account = await getSubgraphAvailabilityOracle(provider, accountIndex)
      await setBalanceIfLocal(provider, chainId, grtTokenAddress, account)
      return account
    },
    getGateway: async (accountIndex?: number) => {
      const account = await getGateway(provider, accountIndex)
      await setBalanceIfLocal(provider, chainId, grtTokenAddress, account)
      return account
    },
    getTestAccounts: async () => {
      const accounts = await getTestAccounts(provider)
      for (const account of accounts) {
        await setBalanceIfLocal(provider, chainId, grtTokenAddress, account)
      }
      return accounts
    },
  }
}

async function setBalanceIfLocal(provider: HardhatEthersProvider, chainId: number, grtTokenAddress: string | Addressable | undefined, account: HardhatEthersSigner) {
  if (grtTokenAddress && [1337, 31337].includes(chainId)) {
    await setGRTBalance(provider, grtTokenAddress, account.address, TEN_MILLION)
  }
}
