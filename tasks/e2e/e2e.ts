import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment, TaskArguments } from 'hardhat/types'
import { TASK_TEST, TASK_RUN } from 'hardhat/builtin-tasks/task-names'
import glob from 'glob'
import { cliOpts } from '../../cli/defaults'
import fs from 'fs'

const CONFIG_TESTS = 'e2e/deployment/config/**/*.test.ts'
const INIT_TESTS = 'e2e/deployment/init/**/*.test.ts'

// Built-in test & run tasks don't support GRE arguments
// so we pass them by overriding GRE config object
const setGraphConfig = async (args: TaskArguments, hre: HardhatRuntimeEnvironment) => {
  const greArgs = ['l1GraphConfig', 'l2GraphConfig', 'addressBook']

  for (const arg of greArgs) {
    if (args[arg]) {
      hre.config.graph[arg] = args[arg]
    }
  }
}

task('e2e', 'Run all e2e tests')
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const testFiles = [
      ...new glob.GlobSync(CONFIG_TESTS).found,
      ...new glob.GlobSync(INIT_TESTS).found,
    ]

    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: testFiles,
    })
  })

task('e2e:config', 'Run deployment configuration e2e tests')
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(CONFIG_TESTS).found
    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:init', 'Run deployment initialization e2e tests')
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(INIT_TESTS).found
    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:scenario', 'Run scenario scripts and e2e tests')
  .addPositionalParam('scenario', 'Name of the scenario to run')
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .addFlag('skipScript', "Don't run scenario script")
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    setGraphConfig(args, hre)

    console.log(`> Running scenario: ${args.scenario}`)

    const script = `e2e/scenarios/${args.scenario}.ts`
    const test = `e2e/scenarios/${args.scenario}.test.ts`

    if (!args.skipScript) {
      if (fs.existsSync(script)) {
        await hre.run(TASK_RUN, {
          script: script,
          noCompile: true,
        })
      } else {
        console.log(`No script found for scenario ${args.scenario}`)
      }
    }

    if (fs.existsSync(test)) {
      await hre.run(TASK_TEST, {
        testFiles: [test],
      })
    } else {
      throw new Error(`No test found for scenario ${args.scenario}`)
    }
  })
