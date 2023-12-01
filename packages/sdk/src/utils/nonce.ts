import { NonceManager } from '@ethersproject/experimental'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import type { providers } from 'ethers'

export class NonceManagerWithAddress extends NonceManager {
  public address: string
  public signerWithAddress: SignerWithAddress

  constructor(signer: SignerWithAddress) {
    super(signer)
    this.address = signer.address
    this.signerWithAddress = signer
  }

  connect(provider: providers.Provider): NonceManager {
    return new NonceManagerWithAddress(this.signerWithAddress.connect(provider))
  }
}
