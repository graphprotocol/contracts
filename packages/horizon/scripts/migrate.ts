require('json5/lib/register')

import hre from 'hardhat'

import { ethers } from 'ethers'
import { expect } from 'chai'
import { ignition } from 'hardhat'

import { UpgradeCurationModule } from '../ignition/modules/periphery/Curation'
import { UpgradeRewardsManagerModule } from '../ignition/modules/periphery/RewardsManager'
import HorizonProxiesModule from '../ignition/modules/core/HorizonProxies'
import HorizonStakingModule from '../ignition/modules/core/HorizonStaking'
import HorizonStakingExtensionModule from '../ignition/modules/core/HorizonStakingExtension'
import ControllerModule from '../ignition/modules/periphery/Controller'
import GraphPaymentsModule from '../ignition/modules/core/GraphPayments'
import PaymentsEscrowModule from '../ignition/modules/core/PaymentsEscrow'
import TAPCollectorModule from '../ignition/modules/core/TAPCollector'

const DISPLAY_UI = true

const HorizonMigrateConfig = removeNFromBigInts(require('../ignition/configs/horizon-migrate.hardhat.json5'))

async function main() {
  console.log(getHorizonBanner())

  const signers = await hre.ethers.getSigners()
  const deployer = signers[0]
  const governor = signers[1]

  console.log('Using deployer account:', deployer.address)
  console.log('Using governor account:', governor.address)

  // Deploy and update proxy with new version of L2Curation
  console.log('=== Upgrading Curation...')
  const { instance: Curation, implementation: CurationImplementation } = await ignition.deploy(
    UpgradeCurationModule, { parameters: HorizonMigrateConfig, displayUi: DISPLAY_UI },
  )

  // Deploy and update proxy with new version of RewardsManager
  console.log('=== Upgrading RewardsManager...')
  const { instance: RewardsManager, implementation: RewardsManagerImplementation } = await ignition.deploy(
    UpgradeRewardsManagerModule, { parameters: HorizonMigrateConfig, displayUi: DISPLAY_UI },
  )

  // Deploy GraphPayments and PaymentsEscrow proxies
  console.log('Deploying GraphPayments and PaymentsEscrow proxies...')
  const {
    GraphPaymentsProxy,
    PaymentsEscrowProxy,
    GraphPaymentsProxyAdmin,
    PaymentsEscrowProxyAdmin,
  } = await ignition.deploy(HorizonProxiesModule, { parameters: HorizonMigrateConfig, displayUi: DISPLAY_UI })

  // // Check if controller has all contracts registered
  // console.log('Checking if controller has all contracts registered...')
  // const { Controller } = await ignition.deploy(ControllerModule, { displayUi: true, parameters: HorizonMigrateConfig })

  // const graphTokenAddress = await Controller.getContractProxy(ethers.keccak256(ethers.toUtf8Bytes('GraphToken')))
  // expect(graphTokenAddress).to.equal(HorizonMigrateConfig.$global.graphTokenProxyAddress, 'GraphToken address does not match')
  // console.log('Controller_GraphToken address:', graphTokenAddress)

  // const stakingAddress = await Controller.getContractProxy(ethers.keccak256(ethers.toUtf8Bytes('Staking')))
  // expect(stakingAddress).to.equal(HorizonMigrateConfig.$global.horizonStakingProxyAddress, 'Staking address does not match')
  // console.log('Controller_Staking address:', stakingAddress)

  // const graphPaymentsAddress = await Controller.getContractProxy(ethers.keccak256(ethers.toUtf8Bytes('GraphPayments')))
  // expect(graphPaymentsAddress).to.equal(GraphPaymentsProxy.target as string, 'GraphPayments address does not match')
  // console.log('Controller_GraphPayments address:', graphPaymentsAddress)

  // const paymentsEscrowAddress = await Controller.getContractProxy(ethers.keccak256(ethers.toUtf8Bytes('PaymentsEscrow')))
  // expect(paymentsEscrowAddress).to.equal(PaymentsEscrowProxy.target as string, 'PaymentsEscrow address does not match')
  // console.log('Controller_PaymentsEscrow address:', paymentsEscrowAddress)

  // const epochManagerAddress = await Controller.getContractProxy(ethers.keccak256(ethers.toUtf8Bytes('EpochManager')))
  // expect(epochManagerAddress).to.equal(HorizonMigrateConfig.$global.epochManagerProxyAddress, 'EpochManager address does not match')
  // console.log('Controller_EpochManager address:', epochManagerAddress)

  // const rewardsManagerAddress = await Controller.getContractProxy(ethers.keccak256(ethers.toUtf8Bytes('RewardsManager')))
  // expect(rewardsManagerAddress).to.equal(RewardsManager.target as string, 'RewardsManager address does not match')
  // console.log('Controller_RewardsManager address:', rewardsManagerAddress)

  // const graphTokenGatewayAddress = await Controller.getContractProxy(ethers.keccak256(ethers.toUtf8Bytes('GraphTokenGateway')))
  // expect(graphTokenGatewayAddress).to.equal(HorizonMigrateConfig.$global.graphTokenGatewayProxyAddress, 'GraphTokenGateway address does not match')
  // console.log('Controller_GraphTokenGateway address:', graphTokenGatewayAddress)

  // const graphProxyAdminAddress = await Controller.getContractProxy(ethers.keccak256(ethers.toUtf8Bytes('GraphProxyAdmin')))
  // expect(graphProxyAdminAddress).to.equal(HorizonMigrateConfig.$global.graphProxyAdminAddress, 'GraphProxyAdmin address does not match')
  // console.log('Controller_GraphProxyAdmin address:', graphProxyAdminAddress)

  // const curationAddress = await Controller.getContractProxy(ethers.keccak256(ethers.toUtf8Bytes('Curation')))
  // expect(curationAddress).to.equal(Curation.target as string, 'Curation address does not match')
  // console.log('Controller_Curation address:', curationAddress)
  // console.log('==============================================')

  // // Deploy HorizonStakingExtension
  // console.log('Deploying HorizonStakingExtension...')
  // const { HorizonStakingExtension } = await ignition.deploy(HorizonStakingExtensionModule, { parameters: HorizonMigrateConfig })
  // console.log('HorizonStakingExtension deployed at:', HorizonStakingExtension.target as string)
  // console.log('==============================================')

  // // Deploy HorizonStaking implementation and upgrade proxy
  // console.log('Deploying HorizonStaking implementation...')
  // const { HorizonStakingImplementation, HorizonStaking } = await ignition.deploy(HorizonStakingModule, { parameters: HorizonMigrateConfig })
  // console.log('HorizonStakingImplementation deployed at:', HorizonStakingImplementation.target as string)
  // console.log('HorizonStakingProxy implementation updated')
  // console.log('==============================================')

  // // Deploy GraphPayments implementation and upgrade proxy
  // console.log('Deploying GraphPayments implementation...')
  // const { GraphPayments, GraphPaymentsImplementation } = await ignition.deploy(GraphPaymentsModule, { parameters: HorizonMigrateConfig })
  // console.log('GraphPaymentsImplementation deployed at:', GraphPaymentsImplementation.target as string)
  // console.log('GraphPaymentsProxy implementation updated')
  // console.log('==============================================')

  // // Deploy PaymentsEscrow implementation and upgrade proxy
  // console.log('Deploying PaymentsEscrow implementation...')
  // const { PaymentsEscrow, PaymentsEscrowImplementation } = await ignition.deploy(PaymentsEscrowModule, { parameters: HorizonMigrateConfig })
  // console.log('PaymentsEscrowImplementation deployed at:', PaymentsEscrowImplementation.target as string)
  // console.log('PaymentsEscrowProxy implementation updated')
  // console.log('==============================================')

  // // Deploy TAPCollector
  // console.log('Deploying TAPCollector...')
  // const { TAPCollector } = await ignition.deploy(TAPCollectorModule, { parameters: HorizonMigrateConfig })
  // console.log('TAPCollector deployed at:', TAPCollector.target as string)
  // console.log('==============================================')

  // // Check if parameters are set correctly
  // console.log('Checking if parameters are set correctly...')
  // expect(await HorizonStaking.getMaxThawingPeriod()).to.equal(HorizonMigrateConfig.HorizonStaking.maxThawingPeriod, 'Max thawing period does not match')
  // expect(await GraphPayments.PROTOCOL_PAYMENT_CUT()).to.equal(HorizonMigrateConfig.GraphPayments.protocolPaymentCut, 'Protocol payment cut does not match')
  // expect(await PaymentsEscrow.WITHDRAW_ESCROW_THAWING_PERIOD()).to.equal(HorizonMigrateConfig.PaymentsEscrow.withdrawEscrowThawingPeriod, 'Withdraw escrow thawing period does not match')
  // expect(await TAPCollector.REVOKE_SIGNER_THAWING_PERIOD()).to.equal(HorizonMigrateConfig.TAPCollector.revokeSignerThawingPeriod, 'Revoke signer thawing period does not match')
  // console.log('Parameters are set correctly')
  // console.log('==============================================')

  console.log('Migration successful! 🎉')
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function removeNFromBigInts(obj: any): any {
  // Ignition requires "n" suffix for bigints, but not here
  if (typeof obj === 'string') {
    return obj.replace(/(\d+)n/g, '$1')
  } else if (Array.isArray(obj)) {
    return obj.map(removeNFromBigInts)
  } else if (typeof obj === 'object' && obj !== null) {
    for (const key in obj) {
      obj[key] = removeNFromBigInts(obj[key])
    }
  }
  return obj
}

function getHorizonBanner(): string {
  return `
██╗  ██╗ ██████╗ ██████╗ ██╗███████╗ ██████╗ ███╗   ██╗
██║  ██║██╔═══██╗██╔══██╗██║╚══███╔╝██╔═══██╗████╗  ██║
███████║██║   ██║██████╔╝██║  ███╔╝ ██║   ██║██╔██╗ ██║
██╔══██║██║   ██║██╔══██╗██║ ███╔╝  ██║   ██║██║╚██╗██║
██║  ██║╚██████╔╝██║  ██║██║███████╗╚██████╔╝██║ ╚████║
╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝
                                                        
██╗   ██╗██████╗  ██████╗ ██████╗  █████╗ ██████╗ ███████╗
██║   ██║██╔══██╗██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██╔════╝
██║   ██║██████╔╝██║  ███╗██████╔╝███████║██║  ██║█████╗  
██║   ██║██╔═══╝ ██║   ██║██╔══██╗██╔══██║██║  ██║██╔══╝  
╚██████╔╝██║     ╚██████╔╝██║  ██║██║  ██║██████╔╝███████╗
 ╚═════╝ ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝
`
}
