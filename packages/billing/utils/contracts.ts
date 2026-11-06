import { providers, Signer, Contract } from 'ethers'
import { logger } from './logging'
import { loadArtifact } from './artifacts'
import { Billing, BillingConnector, IERC20WithPermit } from '../build/types'

export interface BillingContracts {
  Billing?: Billing
  BillingConnector?: BillingConnector
  Token?: IERC20WithPermit
}

export const getContractAt = (
  name: string,
  address: string,
  signerOrProvider?: Signer | providers.Provider,
): Contract => {
  return new Contract(address, loadArtifact(name).abi, signerOrProvider)
}

export const loadContracts = (
  billingAddress: string | undefined,
  billingConnectorAddress: string | undefined,
  tokenAddress: string | undefined,
  banxaAddress: string | undefined,
  signerOrProvider?: Signer | providers.Provider,
): BillingContracts => {
  const contracts = {}
  try {
    if (billingAddress) {
      const billing = getContractAt('Billing', billingAddress)
      contracts['Billing'] = billing
      if (signerOrProvider) {
        contracts['Billing'] = contracts['Billing'].connect(signerOrProvider)
      }
    }
    if (billingConnectorAddress) {
      const billingConnector = getContractAt('BillingConnector', billingConnectorAddress)
      contracts['BillingConnector'] = billingConnector
      if (signerOrProvider) {
        contracts['BillingConnector'] = contracts['BillingConnector'].connect(signerOrProvider)
      }
    }
    if (tokenAddress) {
      const token = getContractAt('Token', tokenAddress)
      contracts['Token'] = token
      if (signerOrProvider) {
        contracts['Token'] = contracts['Token'].connect(signerOrProvider)
      }
    }
    if (banxaAddress) {
      const banxaWrapper = getContractAt('BanxaWrapper', banxaAddress)
      contracts['BanxaWrapper'] = banxaWrapper
      if (signerOrProvider) {
        contracts['BanxaWrapper'] = contracts['BanxaWrapper'].connect(signerOrProvider)
      }
    }
  } catch (err) {
    logger.warn(`Could not load contracts`)
  }
  return contracts as BillingContracts
}
