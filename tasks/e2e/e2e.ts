import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment, TaskArguments } from 'hardhat/types'
import { TASK_TEST, TASK_RUN } from 'hardhat/builtin-tasks/task-names'
import glob from 'glob'
import { cliOpts } from '../../cli/defaults'

const CONFIG_TESTS = 'e2e/deployment/config/*.test.ts'
const INIT_TESTS = 'e2e/deployment/init/*.test.ts'

// Built-in test & run tasks don't support our arguments
// we can pass them to GRE via env vars
const setGraphEnvVars = async (args: TaskArguments) => {
  process.env.GRAPH_CONFIG = args.graphConfig
  process.env.ADDRESS_BOOK = args.addressBook
}

task('e2e', 'Run all e2e tests')
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = [...new glob.GlobSync(CONFIG_TESTS).found, ...new glob.GlobSync(INIT_TESTS).found]
    setGraphEnvVars(args)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:config', 'Run deployment configuration e2e tests')
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(CONFIG_TESTS).found
    setGraphEnvVars(args)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:init', 'Run deployment initialization e2e tests')
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(INIT_TESTS).found
    setGraphEnvVars(args)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:scenario', 'Run scenario scripts and e2e tests')
  .addPositionalParam('scenario', 'Name of the scenario to run')
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    setGraphEnvVars(args)
    await hre.run(TASK_RUN, {
      script: `e2e/scenarios/${args.scenario}.ts`,
      noCompile: true,
    })
    await hre.run(TASK_TEST, {
      testFiles: [`e2e/scenarios/${args.scenario}.test.ts`],
    })
  })
