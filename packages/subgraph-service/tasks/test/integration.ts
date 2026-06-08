import { printBanner } from '@graphprotocol/toolshed/utils'
import { glob } from 'glob'
import { TASK_TEST } from 'hardhat/builtin-tasks/task-names'
import { task } from 'hardhat/config'

task('test:integration', 'Runs all integration tests')
  .addParam('phase', 'Test phase to run: "after-transition-period", "after-delegation-slashing-enabled"')
  .setAction(async (taskArgs, hre) => {
    // Get test files for each phase
    const afterTransitionPeriodFiles = await glob('test/integration/after-transition-period/**/*.{js,ts}')

    // Display banner for the current test phase
    printBanner(taskArgs.phase, 'INTEGRATION TESTS: ')

    // Run tests for the current phase
    switch (taskArgs.phase) {
      case 'after-transition-period':
        await hre.run(TASK_TEST, { testFiles: afterTransitionPeriodFiles })
        break
      default:
        throw new Error(
          'Invalid phase. Must be "after-transition-period", "after-delegation-slashing-enabled", or "all"',
        )
    }
  })
