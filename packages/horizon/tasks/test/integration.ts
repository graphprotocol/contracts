import { glob } from 'glob'
import { task } from 'hardhat/config'
import { TASK_TEST } from 'hardhat/builtin-tasks/task-names'

import { printBanner } from 'hardhat-graph-protocol/sdk'

task('test:integration', 'Runs all integration tests')
  .addParam(
    'phase',
    'Test phase to run: "during-transition-period", "after-transition-period", "after-delegation-slashing-enabled"',
  )
  .setAction(async (taskArgs, hre) => {
    // Get test files for each phase
    const duringTransitionPeriodFiles = await glob('test/integration/during-transition-period/**/*.{js,ts}')
    const afterTransitionPeriodFiles = await glob('test/integration/after-transition-period/**/*.{js,ts}')
    const afterDelegationSlashingEnabledFiles = await glob('test/integration/after-delegation-slashing-enabled/**/*.{js,ts}')

    // Display banner for the current test phase
    printBanner(taskArgs.phase, 'INTEGRATION TESTS: ')

    switch (taskArgs.phase) {
      case 'during-transition-period':
        await hre.run(TASK_TEST, { testFiles: duringTransitionPeriodFiles })
        break
      case 'after-transition-period':
        await hre.run(TASK_TEST, { testFiles: afterTransitionPeriodFiles })
        break
      case 'after-delegation-slashing-enabled':
        await hre.run(TASK_TEST, { testFiles: afterDelegationSlashingEnabledFiles })
        break
      default:
        throw new Error(
          'Invalid phase. Must be "during-transition-period", "after-transition-period", "after-delegation-slashing-enabled", or "all"',
        )
    }
  })
