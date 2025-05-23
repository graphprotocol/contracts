import {
  encodeCollectQueryFeesData,
  encodePOIMetadata,
  generateAllocationProof,
  generatePOI,
  generateSignedRAV,
  generateSignerProof,
  ONE_HUNDRED_THOUSAND,
  ONE_THOUSAND,
  PaymentTypes,
  TEN_MILLION,
  ThawRequestType,
} from '@graphprotocol/toolshed'
import hre, { ethers } from 'hardhat'
import { allocationKeys } from './data'
import { randomBigInt } from '@graphprotocol/toolshed/utils'
const PROVISION_THAWING_PERIOD = 2419200n
const PROVISION_MAX_VERIFIER_CUT = 500_000n
const PROVISION_THAWING_PERIOD_B = 2419199n
const PROVISION_MAX_VERIFIER_CUT_B = 900_000n

const GAS_LIMIT = process.env.GAS_LIMIT ? parseInt(process.env.GAS_LIMIT) : 500_000

async function main() {
  const graph = hre.graph()
  const { HorizonStaking, GraphToken, PaymentsEscrow, GraphTallyCollector } = graph.horizon.contracts
  const { SubgraphService, Curation } = graph.subgraphService.contracts

  const { stake, stakeToProvision, delegate, addToDelegationPool } = graph.horizon.actions

  const signers = await graph.accounts.getTestAccounts()
  const deployer = await graph.accounts.getDeployer()
  const gateway = await graph.accounts.getGateway() // note that this wont be the actual gateway address

  const abi = new ethers.AbiCoder()

  console.log('🔄 Generating protocol activity...')
  console.log('- Deployer: ', deployer.address)
  const deployerEthBalance = await ethers.provider.getBalance(deployer.address)
  const deployerGrtBalance = await GraphToken.balanceOf(deployer.address)
  console.log(`   + ETH Balance: ${ethers.formatEther(deployerEthBalance)} ETH`)
  console.log(`   + GRT Balance: ${ethers.formatEther(deployerGrtBalance)} GRT`)
  console.log('- Signers: ', signers.length)

  // Fund signers - top up to 0.01 ETH
  console.log('💸 Funding signers with ETH...')
  for (const signer of [...signers, gateway]) {
    const balance = await ethers.provider.getBalance(signer.address)
    if (balance < ethers.parseEther('0.01')) {
      await deployer.connect(graph.provider).sendTransaction({ to: signer.address, value: ethers.parseEther('0.01') })
    }
  }

  // Fund signers - top up to 10M GRT
  console.log('💰 Funding signers with GRT...')
  for (const signer of [...signers, gateway]) {
    const balance = await GraphToken.balanceOf(signer.address)
    if (balance < TEN_MILLION) {
      await GraphToken.connect(deployer).transfer(signer.address, TEN_MILLION - balance)
    }
  }

  // Stake - random amount between 0 and available balance
  console.log('📈 Staking random amounts...')
  for (const signer of signers) {
    const balance = await GraphToken.balanceOf(signer.address)
    const stakeAmount = randomBigInt(0n, balance)
    await stake(signer, [stakeAmount])
  }

  // Provision - if not exist, create with random amount between 100k and idle stake, otherwise add random amount
  console.log('🔧 Provisioning or adding to provision...')
  for (const signer of signers) {
    const provision = await HorizonStaking.getProvision(signer.address, SubgraphService.target)
    const provisionExists = provision.createdAt !== 0n

    if (provisionExists) {
      const balance = await GraphToken.balanceOf(signer.address)
      const addAmount = randomBigInt(0n, balance)
      await stakeToProvision(signer, [signer.address, SubgraphService.target, addAmount])
    } else {
      const idleStake = await HorizonStaking.getIdleStake(signer.address)
      const provisionAmount = randomBigInt(ONE_HUNDRED_THOUSAND, idleStake - ONE_HUNDRED_THOUSAND)
      await HorizonStaking.connect(signer).provision(signer.address, SubgraphService.target, provisionAmount, PROVISION_MAX_VERIFIER_CUT, PROVISION_THAWING_PERIOD)
    }
  }

  // Unstake - random amount between 0 and idle stake, scaled down by 50%
  console.log('📉 Unstaking random amounts...')
  for (const signer of signers) {
    const idleStake = await HorizonStaking.getIdleStake(signer.address)
    const unstakeAmount = BigInt(Math.floor(Math.random() * Number(idleStake) * 0.5))
    await HorizonStaking.connect(signer).unstake(unstakeAmount)
  }

  // Subgraph Service - register
  console.log('📝 Subgraph Service - registering...')
  for (const signer of signers) {
    const indexer = await SubgraphService.indexers(signer.address)
    const isRegistered = indexer.registeredAt !== 0n
    if (!isRegistered) {
      const paymentsDestination = Math.random() < 0.5 ? signer.address : ethers.ZeroAddress
      const data = abi.encode(['string', 'string', 'address'], ['http://indexer.xyz', '69y7mznpp', paymentsDestination])
      await SubgraphService.connect(signer).register(signer.address, data)
    }
  }

  // Thaw - random amount between 0 and provision tokens free, scaled down by 50%
  console.log('❄️ Thawing provision tokens...')
  for (const signer of signers) {
    const provision = await HorizonStaking.getProvision(signer.address, SubgraphService.target)
    const thawAmount = randomBigInt(0n, (provision.tokens - provision.tokensThawing) / 2n)
    await HorizonStaking.connect(signer).thaw(signer.address, SubgraphService.target, thawAmount)
  }

  // Deprovision/Reprovision - any thawed tokens
  console.log('🧊 Deprovisioning thawed tokens...')
  for (const signer of signers) {
    const thawedTokens = await HorizonStaking.getThawedTokens(ThawRequestType.Provision, signer.address, SubgraphService.target, signer.address)
    if (thawedTokens > 0) {
      const reprovision = Math.random() < 0.5
      if (reprovision) {
        await HorizonStaking.connect(signer).provision(signer.address, ethers.ZeroAddress, 1n, PROVISION_MAX_VERIFIER_CUT, PROVISION_THAWING_PERIOD)
        await HorizonStaking.connect(signer).reprovision(signer.address, SubgraphService.target, ethers.ZeroAddress, 0)
      } else {
        await HorizonStaking.connect(signer).deprovision(signer.address, SubgraphService.target, 0)
      }
    }
  }

  // AddToProvision - random amount between 0 and idle stake, scaled down by 50%
  console.log('➕ Adding to provision...')
  for (const signer of signers) {
    const idleStake = await HorizonStaking.getIdleStake(signer.address)
    const addAmount = randomBigInt(0n, idleStake / 2n)
    await HorizonStaking.connect(signer).addToProvision(signer.address, SubgraphService.target, addAmount)
  }

  // Set provision parameters
  console.log('🔨 Setting provision parameters...')
  for (const signer of signers) {
    await HorizonStaking.connect(signer).setProvisionParameters(
      signer.address,
      SubgraphService.target,
      Math.random() < 0.5 ? PROVISION_MAX_VERIFIER_CUT_B : PROVISION_MAX_VERIFIER_CUT,
      Math.random() < 0.5 ? PROVISION_THAWING_PERIOD_B : PROVISION_THAWING_PERIOD,
    )
  }

  // Subgraph service - start service
  console.log('🚀 Subgraph Service - starting service...')
  for (const [i, signer] of signers.entries()) {
    for (const privateKey of allocationKeys[i]) {
      const wallet = new ethers.Wallet(privateKey)
      const allocation = await SubgraphService.getAllocation(wallet.address)
      if (allocation.createdAt === 0n) {
        const freeAmount = await HorizonStaking.getProviderTokensAvailable(signer.address, SubgraphService.target) - await SubgraphService.allocationProvisionTracker(signer.address)
        if (freeAmount > ONE_THOUSAND) {
          const allocationAmount = randomBigInt(ONE_THOUSAND, freeAmount)
          const subgraphDeploymentId = ethers.keccak256(`0x${i.toString(16).padStart(2, '0')}`)
          const proof = await generateAllocationProof(signer.address, privateKey, SubgraphService.target as string, graph.chainId)
          const data = abi.encode(['bytes32', 'uint256', 'address', 'bytes'], [subgraphDeploymentId, allocationAmount, wallet.address, proof])
          await SubgraphService.connect(signer).startService(signer.address, data, { gasLimit: GAS_LIMIT })
          // Curate
          const curate = Math.random() < 0.5
          if (curate) {
            await GraphToken.connect(signer).approve(Curation.target, 12345n)
            // @ts-expect-error - TODO: Fix this?
            await Curation.connect(signer).mint(subgraphDeploymentId, 12345n, 0)
          }
        }
      }
    }
  }

  // Subgraph service - set payments destination
  console.log('🏦 Subgraph Service - setting payments destination...')
  for (const signer of signers) {
    const paymentsDestination = Math.random() < 0.5 ? signer.address : ethers.ZeroAddress
    await SubgraphService.connect(signer).setPaymentsDestination(paymentsDestination)
  }

  // Delegation cuts
  console.log('✂️ Delegation cuts...')
  for (const signer of signers) {
    const queryFeeCut = randomBigInt(0n, 50_000n)
    const indexerFeeCut = randomBigInt(0n, 50_000n)
    await HorizonStaking.connect(signer).setDelegationFeeCut(signer.address, SubgraphService.target, PaymentTypes.QueryFee, queryFeeCut)
    await HorizonStaking.connect(signer).setDelegationFeeCut(signer.address, SubgraphService.target, PaymentTypes.IndexingRewards, indexerFeeCut)
  }

  // Subgraph service - resize allocation
  console.log('🔄 Subgraph Service - resizing allocation...')
  for (const [i, signer] of signers.entries()) {
    for (const privateKey of allocationKeys[i]) {
      if (Math.random() > 0.5) {
        const wallet = new ethers.Wallet(privateKey)
        const allocation = await SubgraphService.getAllocation(wallet.address)

        if (allocation.createdAt !== 0n && allocation.closedAt === 0n) {
          const resizeAmount = Math.random() > 0.5 ? allocation.tokens * 9n / 10n : allocation.tokens * 11n / 10n
          const freeAmount = await HorizonStaking.getProviderTokensAvailable(signer.address, SubgraphService.target) - await SubgraphService.allocationProvisionTracker(signer.address)
          if (resizeAmount - allocation.tokens < freeAmount) {
            await SubgraphService.connect(signer).resizeAllocation(signer.address, wallet.address, resizeAmount, { gasLimit: GAS_LIMIT })
          }
        }
      }
    }
  }

  // delegate
  console.log('👥 Delegating...')
  for (const signer of signers) {
    const balance = await GraphToken.balanceOf(signer.address)
    const delegationAmount = balance / 100n
    const serviceProvider = signers[Math.floor(Math.random() * signers.length)]
    await delegate(signer, [serviceProvider, SubgraphService.target, delegationAmount, 0n])
  }

  // Add to delegation pool
  console.log('🔁 Adding to delegation pool...')
  for (const signer of signers) {
    const balance = await GraphToken.balanceOf(signer.address)
    const delegationAmount = balance / 500n

    const delegationPool = await HorizonStaking.getDelegationPool(signer.address, SubgraphService.target)
    if (delegationPool.shares > 0) {
      await addToDelegationPool(signer, [signer.address, SubgraphService.target, delegationAmount])
    }
  }

  // Undelegate
  console.log('🔄 Undelegate...')
  for (const signer of signers) {
    for (const serviceProvider of signers) {
      const delegation = await HorizonStaking.getDelegation(serviceProvider, SubgraphService.target, signer.address)
      if (delegation.shares > 0) {
        await HorizonStaking.connect(signer)['undelegate(address,address,uint256)'](serviceProvider, SubgraphService.target, delegation.shares)
      }
    }
  }

  // withdraw delegation
  console.log('💸 Withdrawing delegation...')
  for (const signer of signers) {
    const tokensThawed = await HorizonStaking.getThawedTokens(ThawRequestType.Delegation, signer.address, SubgraphService.target, signer.address)
    if (tokensThawed > 0) {
      await HorizonStaking.connect(signer)['withdrawDelegated(address,address,uint256)'](signer.address, SubgraphService.target, 0)
    }
  }

  // collect indexing fees
  console.log('📊 Collecting indexing fees...')
  for (const [i, signer] of signers.entries()) {
    for (const privateKey of allocationKeys[i]) {
      const wallet = new ethers.Wallet(privateKey)
      const allocation = await SubgraphService.getAllocation(wallet.address)

      const timeSinceCreated = Math.floor(Date.now() / 1000) - Number(allocation.createdAt)
      if (timeSinceCreated > 120 && allocation.createdAt !== 0n && allocation.closedAt === 0n) { // 10 minutes
        const poi = generatePOI('POI')
        const publicPoi = generatePOI('publicPOI')
        const poiMetadata = encodePOIMetadata(222, publicPoi, 1, 10, 0) // random data, doesnt matter
        const data = abi.encode(['address', 'bytes32', 'bytes'], [wallet.address, poi, poiMetadata])
        await SubgraphService.connect(signer).collect(signer.address, PaymentTypes.IndexingRewards, data, { gasLimit: GAS_LIMIT })
      }
    }
  }

  // collect query fees
  console.log('💰 Collecting query fees...')
  const gatewaySigner = new ethers.Wallet('0x6a0d63ca1ff7f0a6d3357fa59c2fb585f5fcf99e2c73d433022504e2147b6cdd') // use a random private key
  const signerAuth = await GraphTallyCollector.authorizations(gatewaySigner.address)

  if (signerAuth.authorizer === ethers.ZeroAddress) {
    const gatewayProof = generateSignerProof(9962283664n, gateway.address, gatewaySigner.privateKey, GraphTallyCollector.target as string, graph.chainId)
    await GraphTallyCollector.connect(gateway).authorizeSigner(gatewaySigner.address, 9962283664n, gatewayProof)
  }

  for (const [i, signer] of signers.entries()) {
    const escrowAccount = await PaymentsEscrow.escrowAccounts(gateway.address, GraphTallyCollector.target, signer.address)
    if (escrowAccount.balance < ONE_HUNDRED_THOUSAND) {
      await GraphToken.connect(gateway).approve(PaymentsEscrow.target, ONE_HUNDRED_THOUSAND - escrowAccount.balance)
      await PaymentsEscrow.connect(gateway).deposit(GraphTallyCollector.target, signer.address, ONE_HUNDRED_THOUSAND - escrowAccount.balance)
    }

    for (const privateKey of allocationKeys[i]) {
      const wallet = new ethers.Wallet(privateKey)
      const collectionId = abi.encode(['address'], [wallet.address])
      const tokensCollected = await GraphTallyCollector.tokensCollected(SubgraphService.target, collectionId, signer.address, gateway.address)
      const { rav, signature } = await generateSignedRAV(
        wallet.address,
        gateway.address,
        signer.address,
        SubgraphService.target as string,
        0,
        tokensCollected + ONE_THOUSAND,
        ethers.toUtf8Bytes(''),
        gatewaySigner.privateKey,
        GraphTallyCollector.target as string,
        graph.chainId,
      )
      const data = encodeCollectQueryFeesData(rav, signature, 0n)
      await SubgraphService.connect(signer).collect(signer.address, 0, data, { gasLimit: GAS_LIMIT })
    }
  }

  // Subgraph service - stop service
  console.log('🛑 Subgraph Service - stopping service...')
  for (const [i, signer] of signers.entries()) {
    for (const privateKey of allocationKeys[i]) {
      const wallet = new ethers.Wallet(privateKey)
      const allocation = await SubgraphService.getAllocation(wallet.address)

      if (allocation.createdAt !== 0n && allocation.closedAt === 0n) {
        if (Math.random() < 0.35) {
          await SubgraphService.connect(signer).stopService(signer.address, abi.encode(['address'], [wallet.address]))
        }
      }
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
