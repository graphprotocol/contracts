import { TASK_TEST } from 'hardhat/builtin-tasks/task-names'
import { task } from 'hardhat/config'
import { glob } from 'glob'

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
    console.log(getTestPhaseBanner(taskArgs.phase))
    
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

function getTestPhaseBanner(phase: string): string {
  const title = phase
    .split('-')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')
  
  const baseText = 'INTEGRATION TESTS: '
  const fullText = baseText + title
  
  // Calculate minimum banner width needed for the text
  const contentWidth = fullText.length
  const bannerWidth = Math.max(47, contentWidth + 10) // Add padding
  
  // Create the centered text line
  const paddingLeft = Math.floor((bannerWidth - contentWidth) / 2)
  const paddingRight = bannerWidth - contentWidth - paddingLeft
  const centeredLine = '|' + ' '.repeat(paddingLeft) + fullText + ' '.repeat(paddingRight) + '|'
  
  // Create empty line with correct width
  const emptyLine = '|' + ' '.repeat(bannerWidth) + '|'
  
  // Create border with correct width
  const border = '+' + '-'.repeat(bannerWidth) + '+'
  
  return `
${border}
${emptyLine}
${centeredLine}
${emptyLine}
${border}
`
}