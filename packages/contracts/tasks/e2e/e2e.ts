import { HardhatRuntimeEnvironment, TaskArguments } from 'hardhat/types'
import { TASK_TEST } from 'hardhat/builtin-tasks/task-names'
import glob from 'glob'
import fs from 'fs'
import { runScriptWithHardhat } from 'hardhat/internal/util/scripts-runner'
import { isGraphL1ChainId } from '@graphprotocol/sdk'
import { greTask } from '@graphprotocol/sdk/gre'

const CONFIG_TESTS = 'test/e2e/deployment/config/**/*.test.ts'
const INIT_TESTS = 'test/e2e/deployment/init/**/*.test.ts'

// Built-in test & run tasks don't support GRE arguments
// so we pass them by overriding GRE config object
const setGraphConfig = (args: TaskArguments, hre: HardhatRuntimeEnvironment) => {
  const greArgs = [
    'graphConfig',
    'l1GraphConfig',
    'l2GraphConfig',
    'addressBook',
    'disableSecureAccounts',
    'fork',
  ]

  for (const arg of greArgs) {
    if (args[arg]) {
      if (arg === 'graphConfig') {
        const l1 = isGraphL1ChainId(hre.config.networks[hre.network.name].chainId)
        hre.config.graph[l1 ? 'l1GraphConfig' : 'l2GraphConfig'] = args[arg]
      } else {
        hre.config.graph[arg] = args[arg]
      }
    }
  }
}

greTask('e2e', 'Run all e2e tests')
  .addFlag('skipBridge', 'Skip bridge tests')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    let testFiles = [
      ...new glob.GlobSync(CONFIG_TESTS).found,
      ...new glob.GlobSync(INIT_TESTS).found,
    ]

    if (args.skipBridge) {
      testFiles = testFiles.filter(file => !/l1|l2/.test(file))
    }

    // Disable secure accounts, we don't need them for this task
    hre.config.graph.disableSecureAccounts = true

    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: testFiles,
    })
  })

greTask('e2e:config', 'Run deployment configuration e2e tests').setAction(
  async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(CONFIG_TESTS).found

    // Disable secure accounts, we don't need them for this task
    hre.config.graph.disableSecureAccounts = true

    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  },
)

greTask('e2e:init', 'Run deployment initialization e2e tests').setAction(
  async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(INIT_TESTS).found

    // Disable secure accounts, we don't need them for this task
    hre.config.graph.disableSecureAccounts = true

    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  },
)

greTask('e2e:scenario', 'Run scenario scripts and e2e tests')
  .addPositionalParam('scenario', 'Name of the scenario to run')
  .addFlag('skipScript', 'Don\'t run scenario script')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    setGraphConfig(args, hre)

    const script = `test/e2e/scenarios/${args.scenario}.ts`
    const test = `test/e2e/scenarios/${args.scenario}.test.ts`

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

greTask('e2e:upgrade', 'Run upgrade tests')
  .addPositionalParam('upgrade', 'Name of the upgrade to run')
  .addFlag('post', 'Wether to run pre/post upgrade scripts')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    setGraphConfig(args, hre)
    await runUpgrade(args, hre, args.post ? 'post' : 'pre')
  })

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function runUpgrade(args: { [key: string]: any }, hre: HardhatRuntimeEnvironment, type: 'pre' | 'post') {
  const script = `test/e2e/upgrades/${args.upgrade}/${type}-upgrade.ts`
  const test = `test/e2e/upgrades/${args.upgrade}/${type}-upgrade.test.ts`

  console.log(`> Running ${type}-upgrade: ${args.upgrade}`)
  console.log(`- script file: ${script}`)
  console.log(`- test file: ${test}`)

  // Run script
  if (fs.existsSync(script)) {
    console.log(`> Running ${type}-upgrade script: ${script}`)
    await runScriptWithHardhat(hre.hardhatArguments, script, [
      args.addressBook,
      args.graphConfig,
      args.l1GraphConfig,
      args.l2GraphConfig,
      args.disableSecureAccounts,
      args.fork,
    ])
  }

  // Run test
  if (fs.existsSync(test)) {
    console.log(`> Running ${type}-upgrade test: ${test}`)
    await hre.run(TASK_TEST, {
      testFiles: [test],
    })
  }
}
