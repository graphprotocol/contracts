import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { askConfirm, getTokenLockManagerOrFail, isValidAddressOrFail, prettyEnv, waitTransaction } from './create'
import consola from 'consola'
import { formatEther, parseEther } from 'ethers/lib/utils'

const logger = consola.create({})

task('manager-setup-auth', 'Setup default authorized functions in the manager')
  .addParam('targetAddress', 'Target address for function calls')
  .addParam('managerName', 'Name of the token lock manager deployment', 'GraphTokenLockManager')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    // Get contracts
    const manager = await getTokenLockManagerOrFail(hre, taskArgs.managerName)

    logger.info('Setting up authorized functions...')
    logger.log(`> GraphTokenLockManager: ${manager.address}`)
    logger.log(`> Staking: ${taskArgs.targetAddress}`)

    // Prepare
    logger.log(await prettyEnv(hre))

    // Validations
    isValidAddressOrFail(taskArgs.targetAddress)

    // Setup authorized functions
    const signatures = [
      'stake(uint256)',
      'unstake(uint256)',
      'withdraw()',
      'delegate(address,uint256)',
      'undelegate(address,uint256)',
      'withdrawDelegated(address,address)',
      'setDelegationParameters(uint32,uint32,uint32)',
      'setOperator(address,bool)',
    ]

    logger.info('The following signatures will be authorized:')
    logger.info(signatures)

    if (await askConfirm()) {
      // Setup authorized functions
      logger.info('Setup authorized functions...')
      const targets = Array(signatures.length).fill(taskArgs.targetAddress)
      const tx1 = await manager.setAuthFunctionCallMany(signatures, targets)
      await waitTransaction(tx1)
      logger.success('Done!\n')

      // Setup authorized token destinations
      logger.info('Setup authorized destinations...')
      const tx2 = await manager.addTokenDestination(taskArgs.targetAddress)
      await waitTransaction(tx2)
    }
  })

task('manager-deposit', 'Deposit fund into the manager')
  .addParam('amount', 'Amount to deposit in GRT')
  .addParam('managerName', 'Name of the token lock manager deployment', 'GraphTokenLockManager')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    // Get contracts
    const manager = await getTokenLockManagerOrFail(hre, taskArgs.managerName)

    // Prepare
    logger.log(await prettyEnv(hre))

    const tokenAddress = await manager.token()

    logger.info('Using:')
    logger.log(`> GraphToken: ${tokenAddress}`)
    logger.log(`> GraphTokenLockMasterCopy: ${await manager.masterCopy()}`)
    logger.log(`> GraphTokenLockManager: ${manager.address}`)

    // Deposit funds
    logger.log(`You are depositing ${taskArgs.amount} into ${manager.address}...`)
    if (await askConfirm()) {
      const weiAmount = parseEther(taskArgs.amount)

      logger.log('Approve...')
      const grt = await hre.ethers.getContractAt('ERC20', tokenAddress)
      const tx1 = await grt.approve(manager.address, weiAmount)
      await waitTransaction(tx1)

      logger.log('Deposit...')
      const tx2 = await manager.deposit(weiAmount)
      await waitTransaction(tx2)
    }
  })

task('manager-withdraw', 'Withdraw fund from the manager')
  .addParam('amount', 'Amount to deposit in GRT')
  .addParam('managerName', 'Name of the token lock manager deployment', 'GraphTokenLockManager')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    // Get contracts
    const manager = await getTokenLockManagerOrFail(hre, taskArgs.managerName)

    // Prepare
    logger.log(await prettyEnv(hre))

    const tokenAddress = await manager.token()

    logger.info('Using:')
    logger.log(`> GraphToken: ${tokenAddress}`)
    logger.log(`> GraphTokenLockMasterCopy: ${await manager.masterCopy()}`)
    logger.log(`> GraphTokenLockManager: ${manager.address}`)

    // Withdraw funds
    logger.log(`You are withdrawing ${taskArgs.amount} from ${manager.address}...`)
    if (await askConfirm()) {
      const weiAmount = parseEther(taskArgs.amount)

      logger.log('Deposit...')
      const tx = await manager.withdraw(weiAmount)
      await waitTransaction(tx)
    }
  })

task('manager-balance', 'Get current manager balance')
  .addParam('managerName', 'Name of the token lock manager deployment', 'GraphTokenLockManager')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    // Get contracts
    const manager = await getTokenLockManagerOrFail(hre, taskArgs.managerName)

    // Prepare
    logger.log(await prettyEnv(hre))

    const tokenAddress = await manager.token()
    const managerOwnerAddress = await manager.owner()

    logger.info('Using:')
    logger.log(`> GraphToken: ${tokenAddress}`)
    logger.log(`> GraphTokenLockMasterCopy: ${await manager.masterCopy()}`)
    logger.log(`> GraphTokenLockManager: ${manager.address} owner: ${managerOwnerAddress}`)

    const grt = await hre.ethers.getContractAt('ERC20', tokenAddress)
    const balance = await grt.balanceOf(manager.address)
    logger.log('Current Manager balance is ', formatEther(balance))
  })

task('manager-transfer-ownership', 'Transfer ownership of the manager')
  .addParam('owner', 'Address of the new owner')
  .addParam('managerName', 'Name of the token lock manager deployment', 'GraphTokenLockManager')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const manager = await getTokenLockManagerOrFail(hre, taskArgs.managerName)

    // Validate current owner
    const tokenLockManagerOwner = await manager.owner()
    const { deployer } = await hre.getNamedAccounts()
    if (tokenLockManagerOwner !== deployer) {
      logger.error('Only the owner can transfer ownership')
      process.exit(1)
    }

    logger.info(`Manager address: ${manager.address}}`)
    logger.info(`Current owner: ${tokenLockManagerOwner}`)
    logger.info(`New owner: ${taskArgs.owner}`)

    if (!(await askConfirm())) {
      logger.log('Cancelled')
      process.exit(1)
    }

    // Transfer ownership
    await manager.transferOwnership(taskArgs.owner)
  })
