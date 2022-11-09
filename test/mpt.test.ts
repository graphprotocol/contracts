import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber, Event } from 'ethers'
import { keccak256, RLP } from 'ethers/lib/utils'
import { Trie } from '@ethereumjs/trie'

import { MerklePatriciaProofVerifierMock } from '../build/types/MerklePatriciaProofVerifierMock'
import { deployContract } from './lib/deployment'
import { Account, getAccounts, randomHexBytes } from './lib/testHelpers'

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

  it('verifies a valid proof of exclusion for the empty tree', async function () {
    const trie = new Trie()
    const key = Buffer.from('whatever')
    const proof = await trie.createProof(key)

    const encodedProof = encodeProofRLP(proof)

    const val = await mpt.extractProofValue(
      bufferToHex(trie.root()),
      bufferToHex(key),
      encodedProof,
    )
    expect(val).to.equal('0x')
  })

  it('rejects an invalid root for the empty tree', async function () {
    const trie = new Trie()
    const key = Buffer.from('whatever')
    const proof = await trie.createProof(key)

    const encodedProof = encodeProofRLP(proof)

    const call = mpt.extractProofValue(randomHexBytes(), bufferToHex(key), encodedProof)
    await expect(call).revertedWith('MPT: invalid empty tree root')
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
  it('verifies a valid proof of exclusion based on a divergent node', async function () {
    const trie = new Trie()
    const key = Buffer.from('foo')

    // We add a few more random values
    await trie.put(Buffer.from('food'), Buffer.from('baz'))
    await trie.put(Buffer.from('fob'), Buffer.from('bat'))
    await trie.put(Buffer.from('zort'), Buffer.from('narf'))

    const proof = await trie.createProof(key)

    // The path for "food" should form a divergent path for "foo"
    const encodedProof = encodeProofRLP(proof)

    const val = await mpt.extractProofValue(
      bufferToHex(trie.root()),
      bufferToHex(key),
      encodedProof,
    )
    expect(val).to.equal('0x')
  })
  it('verifies a valid proof of exclusion based on a leaf node', async function () {
    const trie = new Trie()
    const key = Buffer.from('food')

    // We add a few more random values
    await trie.put(Buffer.from('foo'), Buffer.from('baz'))

    const proof = await trie.createProof(key)

    // The path for "foo" should be a leaf node, which proofs "food" is excluded
    const encodedProof = encodeProofRLP(proof)

    const val = await mpt.extractProofValue(
      bufferToHex(trie.root()),
      bufferToHex(key),
      encodedProof,
    )
    expect(val).to.equal('0x')
  })
  it('verifies a valid proof of exclusion based on an empty leaf on a branch node', async function () {
    const trie = new Trie()
    const key = Buffer.from('zork')

    await trie.put(Buffer.from('zor'), Buffer.from('baz'))

    // The fact that we have two keys that only differ in the
    // last nibble gives us a proof that ends with a branch node
    // with an empty value for the last nibble.
    await trie.put(Buffer.from('zorl'), Buffer.from('bart'))
    await trie.put(Buffer.from('zorm'), Buffer.from('bort'))

    const proof = await trie.createProof(key)
    const encodedProof = encodeProofRLP(proof)

    const val = await mpt.extractProofValue(
      bufferToHex(trie.root()),
      bufferToHex(key),
      encodedProof,
    )
    expect(val).eq('0x')
  })
  it('rejects a proof with an invalid value', async function () {
    const trie = new Trie()
    const key = Buffer.from('foo')
    const value = Buffer.from('bar')
    await trie.put(key, value)

    // We add a few more random values
    await trie.put(Buffer.from('food'), Buffer.from('baz'))
    await trie.put(Buffer.from('fob'), Buffer.from('bat'))
    await trie.put(Buffer.from('zort'), Buffer.from('narf'))

    const proof = await trie.createProof(key)

    const decodedProof = proof.map((v) => RLP.decode(bufferToHex(v)))
    decodedProof[3][16] = bufferToHex(Buffer.from('wrong'))
    const reEncodedProof = decodedProof.map((v) => Buffer.from(RLP.encode(v).slice(2), 'hex'))

    const encodedProof = encodeProofRLP(reEncodedProof)

    const call = mpt.extractProofValue(bufferToHex(trie.root()), bufferToHex(key), encodedProof)
    await expect(call).revertedWith('MPT: invalid node hash')
  })
  it('rejects a proof of exclusion where the divergent node is not last', async function () {
    const trie = new Trie()
    const key = Buffer.from('foo')

    // We add a few more random values
    await trie.put(Buffer.from('food'), Buffer.from('baz'))
    await trie.put(Buffer.from('fob'), Buffer.from('bat'))
    await trie.put(Buffer.from('zort'), Buffer.from('narf'))

    const proof = await trie.createProof(key)

    const decodedProof = proof.map((v) => RLP.decode(bufferToHex(v)))
    // We add a random node to the end of the proof
    decodedProof.push(bufferToHex(Buffer.from('wrong')))
    const reEncodedProof = decodedProof.map((v) => Buffer.from(RLP.encode(v).slice(2), 'hex'))
    const encodedProof = encodeProofRLP(reEncodedProof)

    const call = mpt.extractProofValue(bufferToHex(trie.root()), bufferToHex(key), encodedProof)
    await expect(call).revertedWith('MPT: divergent node not last')
  })
  it('rejects a proof of inclusion with garbage at the end', async function () {
    const trie = new Trie()
    const key = Buffer.from('foo')
    const value = Buffer.from('bar')
    await trie.put(key, value)

    // We add a few more random values
    await trie.put(Buffer.from('food'), Buffer.from('baz'))
    await trie.put(Buffer.from('fob'), Buffer.from('bat'))
    await trie.put(Buffer.from('zort'), Buffer.from('narf'))

    const proof = await trie.createProof(key)
    const decodedProof = proof.map((v) => RLP.decode(bufferToHex(v)))
    // We add a random node to the end of the proof
    decodedProof.push(bufferToHex(Buffer.from('wrong')))
    const reEncodedProof = decodedProof.map((v) => Buffer.from(RLP.encode(v).slice(2), 'hex'))
    const encodedProof = encodeProofRLP(reEncodedProof)

    const call = mpt.extractProofValue(bufferToHex(trie.root()), bufferToHex(key), encodedProof)
    await expect(call).revertedWith('MPT: end not last')
  })
  it('rejects a proof of inclusion with garbage after a leaf node', async function () {
    const trie = new Trie()
    const key = Buffer.from('foo')
    const value = Buffer.from('bar')
    await trie.put(key, value)

    const proof = await trie.createProof(key)
    const decodedProof = proof.map((v) => RLP.decode(bufferToHex(v)))
    // We add a random node to the end of the proof
    decodedProof.push(bufferToHex(Buffer.from('wrong')))
    const reEncodedProof = decodedProof.map((v) => Buffer.from(RLP.encode(v).slice(2), 'hex'))
    const encodedProof = encodeProofRLP(reEncodedProof)

    const call = mpt.extractProofValue(bufferToHex(trie.root()), bufferToHex(key), encodedProof)
    await expect(call).revertedWith('MPT: leaf node not last')
  })
  it('rejects a truncated proof of inclusion', async function () {
    const trie = new Trie()
    const key = Buffer.from('foo')
    const value = Buffer.from('bar')
    await trie.put(key, value)

    // We add a few more random values
    await trie.put(Buffer.from('food'), Buffer.from('baz'))
    await trie.put(Buffer.from('fob'), Buffer.from('bat'))
    await trie.put(Buffer.from('zort'), Buffer.from('narf'))

    const proof = await trie.createProof(key)
    const decodedProof = proof.map((v) => RLP.decode(bufferToHex(v)))
    // We remove some nodes from the end, leaving a non-leaf node last
    const truncatedProof = [decodedProof[0], decodedProof[1]]
    const reEncodedProof = truncatedProof.map((v) => Buffer.from(RLP.encode(v).slice(2), 'hex'))
    const encodedProof = encodeProofRLP(reEncodedProof)

    const call = mpt.extractProofValue(bufferToHex(trie.root()), bufferToHex(key), encodedProof)
    await expect(call).revertedWith('MPT: non-leaf node last')
  })
  it('rejects a proof of exclusion with a non-last empty byte sequence', async function () {
    const trie = new Trie()
    const key = Buffer.from('zork')

    await trie.put(Buffer.from('zor'), Buffer.from('baz'))

    // The fact that we have two keys that only differ in the
    // last nibble gives us a proof that ends with a branch node
    // with an empty value for the last nibble.
    await trie.put(Buffer.from('zorl'), Buffer.from('bart'))
    await trie.put(Buffer.from('zorm'), Buffer.from('bort'))

    const proof = await trie.createProof(key)
    const decodedProof = proof.map((v) => RLP.decode(bufferToHex(v)))
    // We add a random node to the end of the proof
    decodedProof.push(bufferToHex(Buffer.from('wrong')))
    const reEncodedProof = decodedProof.map((v) => Buffer.from(RLP.encode(v).slice(2), 'hex'))
    const encodedProof = encodeProofRLP(reEncodedProof)

    const call = mpt.extractProofValue(bufferToHex(trie.root()), bufferToHex(key), encodedProof)
    await expect(call).revertedWith('MPT: empty leaf not last')
  })
  it('verifies an inclusion proof for a trie that uses hashed keys', async function () {
    const trie = new Trie({ useKeyHashing: true })
    const key = Buffer.from('something')
    const value = Buffer.from('a value')
    await trie.put(key, value)

    // We add a few more random values
    await trie.put(Buffer.from('something else'), Buffer.from('baz'))
    await trie.put(Buffer.from('more stuff'), Buffer.from('bat'))
    await trie.put(Buffer.from('zort'), Buffer.from('narf'))

    const proof = await trie.createProof(key)

    const encodedProof = encodeProofRLP(proof)
    const val = await mpt.extractProofValue(bufferToHex(trie.root()), keccak256(key), encodedProof)
    await expect(val).eq(bufferToHex(value))
  })
  it('verifies an exclusion proof for a trie that uses hashed keys', async function () {
    const trie = new Trie({ useKeyHashing: true })
    const key = Buffer.from('something')

    // We add a few more random values
    await trie.put(Buffer.from('something else'), Buffer.from('baz'))
    await trie.put(Buffer.from('more stuff'), Buffer.from('bat'))
    await trie.put(Buffer.from('zort'), Buffer.from('narf'))

    const proof = await trie.createProof(key)

    const encodedProof = encodeProofRLP(proof)
    const val = await mpt.extractProofValue(bufferToHex(trie.root()), keccak256(key), encodedProof)
    await expect(val).eq('0x')
  })
})
