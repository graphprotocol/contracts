import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment, TaskArguments } from 'hardhat/types'
import { TASK_TEST } from 'hardhat/builtin-tasks/task-names'
import glob from 'glob'
import { cliOpts } from '../../cli/defaults'
import fs from 'fs'
import { isL1 } from '../../gre/helpers/chain'
import { runScriptWithHardhat } from 'hardhat/internal/util/scripts-runner'

const CONFIG_TESTS = 'e2e/deployment/config/**/*.test.ts'
const INIT_TESTS = 'e2e/deployment/init/**/*.test.ts'

// Built-in test & run tasks don't support GRE arguments
// so we pass them by overriding GRE config object
const setGraphConfig = async (args: TaskArguments, hre: HardhatRuntimeEnvironment) => {
  const greArgs = [
    'graphConfig',
    'l1GraphConfig',
    'l2GraphConfig',
    'addressBook',
    'disableSecureAccounts',
  ]

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
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addFlag('skipBridge', 'Skip bridge tests')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    let testFiles = [
      ...new glob.GlobSync(CONFIG_TESTS).found,
      ...new glob.GlobSync(INIT_TESTS).found,
    ]

    if (args.skipBridge) {
      testFiles = testFiles.filter((file) => !['l1', 'l2'].includes(file.split('/')[3]))
    }

    // Disable secure accounts, we don't need them for this task
    hre.config.graph.disableSecureAccounts = true

    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: testFiles,
    })
  })

task('e2e:config', 'Run deployment configuration e2e tests')
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(CONFIG_TESTS).found

    // Disable secure accounts, we don't need them for this task
    hre.config.graph.disableSecureAccounts = true

    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:init', 'Run deployment initialization e2e tests')
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(INIT_TESTS).found

    // Disable secure accounts, we don't need them for this task
    hre.config.graph.disableSecureAccounts = true

    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:scenario', 'Run scenario scripts and e2e tests')
  .addPositionalParam('scenario', 'Name of the scenario to run')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l1GraphConfig', cliOpts.graphConfig.description)
  .addOptionalParam('l2GraphConfig', cliOpts.graphConfig.description)
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
          args.addressBook,
          args.graphConfig,
          args.l1GraphConfig,
          args.l2GraphConfig,
          args.disableSecureAccounts,
        ])
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
