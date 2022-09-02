import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment, TaskArguments } from 'hardhat/types'
import { TASK_TEST, TASK_RUN } from 'hardhat/builtin-tasks/task-names'
import glob from 'glob'
import { cliOpts } from '../../cli/defaults'
import fs from 'fs'
import { isL1 } from '../../gre/helpers/network'
import { runScriptWithHardhat } from 'hardhat/internal/util/scripts-runner'

const CONFIG_TESTS = 'e2e/deployment/config/**/*.test.ts'
const INIT_TESTS = 'e2e/deployment/init/**/*.test.ts'

// Built-in test & run tasks don't support GRE arguments
// so we pass them by overriding GRE config object
const setGraphConfig = async (args: TaskArguments, hre: HardhatRuntimeEnvironment) => {
  const greArgs = ['graphConfig', 'l1GraphConfig', 'l2GraphConfig', 'addressBook']

  for (const arg of greArgs) {
    if (args[arg]) {
      if (arg === 'graphConfig') {
        const l1 = isL1(hre.config.networks[hre.network.name].chainId)
        hre.config.graph[l1 ? 'l1GraphConfig' : 'l2GraphConfig'] = args[arg]
      } else {
        hre.config.graph[arg] = args[arg]
      }
    }
  }
}

task('e2e', 'Run all e2e tests')
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
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
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(CONFIG_TESTS).found
    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:init', 'Run deployment initialization e2e tests')
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(INIT_TESTS).found
    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:scenario', 'Run scenario scripts and e2e tests')
  .addPositionalParam('scenario', 'Name of the scenario to run')
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addFlag('skipScript', "Don't run scenario script")
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    setGraphConfig(args, hre)

    const script = `e2e/scenarios/${args.scenario}.ts`
    const test = `e2e/scenarios/${args.scenario}.test.ts`

    console.log(`> Running scenario: ${args.scenario}`)
    console.log(`- script file: ${script}`)
    console.log(`- test file: ${test}`)

    if (!args.skipScript) {
      if (fs.existsSync(script)) {
        await runScriptWithHardhat(hre.hardhatArguments, script, [
          args.graphConfig,
          args.addressBook,
        ])
        // await hre.run(TASK_RUN, {
        //   script: script,
        //   noCompile: true,
        //   ...args,
        // })
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
