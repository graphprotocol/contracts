import type { BigNumber, Contract } from 'ethers'

export type ContractList<T extends string = string> = Partial<Record<T, Contract>>

export type ContractParam = string | BigNumber | number
