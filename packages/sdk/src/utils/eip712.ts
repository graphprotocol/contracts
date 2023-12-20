import { eip712 } from '@graphprotocol/common-ts/dist/attestations'
import { BigNumber, BytesLike, Signature } from 'ethers'
import { SigningKey, keccak256 } from 'ethers/lib/utils'

export interface Permit {
  owner: string
  spender: string
  value: BigNumber
  nonce: BigNumber
  deadline: BigNumber
}

const PERMIT_TYPE_HASH = eip712.typeHash(
  'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)',
)

export function signPermit(
  signer: BytesLike,
  chainId: number,
  contractAddress: string,
  permit: Permit,
  salt: string,
): Signature {
  const domainSeparator = eip712.domainSeparator({
    name: 'Graph Token',
    version: '0',
    chainId,
    verifyingContract: contractAddress,
    salt: salt,
  })
  const hashEncodedPermit = hashEncodePermit(permit)
  const message = eip712.encode(domainSeparator, hashEncodedPermit)
  const messageHash = keccak256(message)
  const signingKey = new SigningKey(signer)
  return signingKey.signDigest(messageHash)
}

function hashEncodePermit(permit: Permit) {
  return eip712.hashStruct(
    PERMIT_TYPE_HASH,
    ['address', 'address', 'uint256', 'uint256', 'uint256'],
    [permit.owner, permit.spender, permit.value, permit.nonce, permit.deadline],
  )
}
