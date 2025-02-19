import { TASK_TEST } from 'hardhat/builtin-tasks/task-names'
import { task } from 'hardhat/config'
import { glob } from 'glob'

task('test:integration', 'Runs all integration tests')
  .addOptionalParam('deployType', 'Chose between deploy or migrate. If not specified, skips deployment.')
  .setAction(async (taskArgs, hre) => {
    // Require hardhat or localhost network
    if (hre.network.name !== 'hardhat' && hre.network.name !== 'localhost') {
      throw new Error('Integration tests can only be run on the hardhat or localhost network')
    }

    // Handle deployment if mode is specified
    if (taskArgs.deployType) {
      switch (taskArgs.deployType.toLowerCase()) {
        case 'deploy':
          await hre.run('deploy:protocol')
          break
        default:
          throw new Error('Invalid mode. Must be either deploy or migrate')
      }
    }

    const testFiles = await glob('test/integration/**/*.{js,ts}')

    // Initialize graph config if not exists
    hre.config.graph = hre.config.graph || {}
    hre.config.graph.deployments = hre.config.graph.deployments || {}
    hre.config.graph.deployments.horizon = './addresses-local.json'

    await hre.run(TASK_TEST, { testFiles: testFiles })
  })
