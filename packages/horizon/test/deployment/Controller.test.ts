import hre from 'hardhat'

import { expect } from 'chai'
import { toUtf8Bytes } from 'ethers'

const graph = hre.graph()
const addressBook = graph.horizon.addressBook
const Controller = graph.horizon.contracts.Controller

describe('Controller', function () {
  it('should have GraphToken registered', async function () {
    const graphToken = await Controller.getContractProxy(hre.ethers.keccak256(toUtf8Bytes('GraphToken')))
    expect(graphToken).to.equal(addressBook.getEntry('L2GraphToken').address)
  })

  it('should have HorizonStaking registered', async function () {
    const horizonStaking = await Controller.getContractProxy(hre.ethers.keccak256(toUtf8Bytes('Staking')))
    expect(horizonStaking).to.equal(addressBook.getEntry('HorizonStaking').address)
  })

  it('should have GraphPayments registered', async function () {
    const graphPayments = await Controller.getContractProxy(hre.ethers.keccak256(toUtf8Bytes('GraphPayments')))
    expect(graphPayments).to.equal(addressBook.getEntry('GraphPayments').address)
  })

  it('should have PaymentsEscrow registered', async function () {
    const paymentsEscrow = await Controller.getContractProxy(hre.ethers.keccak256(toUtf8Bytes('PaymentsEscrow')))
    expect(paymentsEscrow).to.equal(addressBook.getEntry('PaymentsEscrow').address)
  })

  it('should have EpochManager registered', async function () {
    const epochManager = await Controller.getContractProxy(hre.ethers.keccak256(toUtf8Bytes('EpochManager')))
    expect(epochManager).to.equal(addressBook.getEntry('EpochManager').address)
  })

  it('should have RewardsManager registered', async function () {
    const rewardsManager = await Controller.getContractProxy(hre.ethers.keccak256(toUtf8Bytes('RewardsManager')))
    expect(rewardsManager).to.equal(addressBook.getEntry('RewardsManager').address)
  })

  it('should have GraphTokenGateway registered', async function () {
    const graphTokenGateway = await Controller.getContractProxy(hre.ethers.keccak256(toUtf8Bytes('GraphTokenGateway')))
    expect(graphTokenGateway).to.equal(addressBook.getEntry('L2GraphTokenGateway').address)
  })

  it('should have GraphProxyAdmin registered', async function () {
    const graphProxyAdmin = await Controller.getContractProxy(hre.ethers.keccak256(toUtf8Bytes('GraphProxyAdmin')))
    expect(graphProxyAdmin).to.equal(addressBook.getEntry('GraphProxyAdmin').address)
  })

  it('should have Curation registered', async function () {
    const curation = await Controller.getContractProxy(hre.ethers.keccak256(toUtf8Bytes('Curation')))
    expect(curation).to.equal(addressBook.getEntry('L2Curation').address)
  })
})
