import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber, Event } from 'ethers'
import { RLP } from 'ethers/lib/utils'
import { Trie } from '@ethereumjs/trie'

import { MerklePatriciaProofVerifierMock } from '../build/types/MerklePatriciaProofVerifierMock'
import { deployContract } from './lib/deployment'
import { Account, getAccounts } from './lib/testHelpers'

const bufferToHex = (buf: Buffer): string => {
  return '0x' + buf.toString('hex')
}

const encodeProofRLP = (proof: Array<Buffer>): string => {
  const decodedArr = proof.map((v) => RLP.decode(bufferToHex(v)))
  return RLP.encode(decodedArr)
}

describe('MerklePatriciaProofVerifier', () => {
  let me: Account
  let mpt: MerklePatriciaProofVerifierMock

  before(async function () {
    ;[me] = await getAccounts()
    mpt = (await deployContract(
      'MerklePatriciaProofVerifierMock',
      me.signer,
    )) as unknown as MerklePatriciaProofVerifierMock
  })

  it('verifies a valid proof of inclusion', async function () {
    const trie = new Trie()
    const key = Buffer.from('foo')
    const value = Buffer.from('bar')
    await trie.put(key, value)

    // We add a few more random values
    await trie.put(Buffer.from('food'), Buffer.from('baz'))
    await trie.put(Buffer.from('fob'), Buffer.from('bat'))
    await trie.put(Buffer.from('zort'), Buffer.from('narf'))

    const proof = await trie.createProof(key)

    const encodedProof = encodeProofRLP(proof)

    const val = await mpt.extractProofValue(
      bufferToHex(trie.root()),
      bufferToHex(key),
      encodedProof,
    )
    expect(val).to.equal(bufferToHex(value))
  })
  it('verifies a valid proof of exclusion', async function () {
    const trie = new Trie()
    const key = Buffer.from('foo')

    // We add a few more random values
    await trie.put(Buffer.from('food'), Buffer.from('baz'))
    await trie.put(Buffer.from('fob'), Buffer.from('bat'))
    await trie.put(Buffer.from('zort'), Buffer.from('narf'))

    const proof = await trie.createProof(key)

    const encodedProof = encodeProofRLP(proof)

    const val = await mpt.extractProofValue(
      bufferToHex(trie.root()),
      bufferToHex(key),
      encodedProof,
    )
    expect(val).to.equal('0x')
  })
})
