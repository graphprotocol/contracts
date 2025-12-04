import { ethers } from 'hardhat'
import { task } from 'hardhat/config'
import { loadParams } from '../deploy/lib/params'

// Minimal ABI for legacy GraphProxyAdmin
const GRAPH_PROXY_ADMIN_ABI = [
  'function upgrade(address proxy, address implementation) external',
  'function upgradeAndCall(address proxy, address implementation, bytes data) external'
]

// Usage:
//   pnpm --filter @graphprotocol/issuance-deploy hardhat upgrade:rewards-manager --new-impl 0x... [--call-data 0x...] --network <network>
//
// Params from config/env:
//   - rewardsManager: GraphProxy address of RewardsManager proxy
//   - graphLegacyProxyAdmin: GraphProxyAdmin address that controls RewardsManager
//   - governor: signer to perform the upgrade

task('upgrade:rewards-manager', 'Upgrade RewardsManager via legacy GraphProxyAdmin')
  .addParam('newImpl', 'New RewardsManager implementation address')
  .addOptionalParam('callData', 'Initializer calldata for upgradeAndCall (hex)')
  .setAction(async (args, hre) => {
    const { newImpl, callData } = args as { newImpl: string; callData?: string }

    const params = await loadParams(hre)
    const rewardsManager = params.rewardsManager
    const graphLegacyProxyAdmin = params.graphLegacyProxyAdmin
    const governorAddr = params.governor

    if (!rewardsManager) throw new Error('Missing rewardsManager in params (config/<network>.json or REWARDS_MANAGER env)')
    if (!graphLegacyProxyAdmin)
      throw new Error(
        'Missing graphLegacyProxyAdmin in params (config/<network>.json or GRAPH_LEGACY_PROXY_ADMIN env)',
      )
    const isValid = (() => {
      try {
        const e = ethers as unknown as { utils?: { getAddress?: (a: string) => string }; getAddress?: (a: string) => string }
        if (e.utils?.getAddress) { e.utils.getAddress(newImpl); return true }
        if (e.getAddress) { e.getAddress(newImpl); return true }
        return false
      } catch { return false }
    })()
    if (!isValid) throw new Error('newImpl must be a valid address')

    const signer = governorAddr
      ? await (async () => {
          const signerFromAddr = await hre.ethers.getSigner(governorAddr)
          return signerFromAddr
        })()
      : (await hre.ethers.getSigners())[1]

    const admin = new ethers.Contract(graphLegacyProxyAdmin, GRAPH_PROXY_ADMIN_ABI, signer)

    if (callData && callData !== '0x') {
      console.log(`Upgrading RewardsManager@${rewardsManager} to ${newImpl} with call...`)
      const tx = await admin.upgradeAndCall(rewardsManager, newImpl, callData)
      console.log(`tx: ${tx.hash}`)
      await tx.wait()
    } else {
      console.log(`Upgrading RewardsManager@${rewardsManager} to ${newImpl}...`)
      const tx = await admin.upgrade(rewardsManager, newImpl)
      console.log(`tx: ${tx.hash}`)
      await tx.wait()
    }

    console.log('Upgrade completed')
  })
