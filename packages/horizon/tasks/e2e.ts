import { TASK_TEST } from 'hardhat/builtin-tasks/task-names'
import { task } from 'hardhat/config'
import { glob } from 'glob'

task('test:integration', 'Runs all integration tests')
  .addParam(
    'phase',
    'Test phase to run: "during-transition", "after-transition", "after-delegation-slashing"',
  )
  .setAction(async (taskArgs, hre) => {
    // Get test files for each phase
    const duringTransitionPeriodFiles = await glob('test/integration/during-transition-period/**/*.{js,ts}')
    const afterTransitionPeriodFiles = await glob('test/integration/after-transition-period/**/*.{js,ts}')
    const afterDelegationSlashingEnabledFiles = await glob('test/integration/after-delegation-slashing-enabled/**/*.{js,ts}')

    switch (taskArgs.phase) {
      case 'during-transition':
        await hre.run(TASK_TEST, { testFiles: duringTransitionPeriodFiles })
        break
      case 'after-transition':
        await hre.run(TASK_TEST, { testFiles: afterTransitionPeriodFiles })
        break
      case 'after-delegation-slashing':
        await hre.run(TASK_TEST, { testFiles: afterDelegationSlashingEnabledFiles })
        break
      default:
        throw new Error(
          'Invalid phase. Must be "during-transition", "after-transition", "after-delegation-slashing", or "all"',
        )
    }
  })
