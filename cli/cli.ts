#!/usr/bin/env ts-node
import * as dotenv from 'dotenv'
import yargs from 'yargs'

import { deployCommand } from './commands/deploy'
import { migrateCommand } from './commands/migrate'
import { proxyCommand } from './commands/proxy'
import { protocolCommand } from './commands/protocol'
import { contractsCommand } from './commands/contracts'
import { simulationCommand } from './commands/simulations'
import { airdropCommand } from './commands/airdrop'

import { cliOpts } from './defaults'

dotenv.config()

yargs
  .env(true)
  .option('a', cliOpts.addressBook)
  .option('m', cliOpts.mnemonic)
  .option('p', cliOpts.providerUrl)
  .option('n', cliOpts.accountNumber)
  .command(deployCommand)
  .command(migrateCommand)
  .command(proxyCommand)
  .command(protocolCommand)
  .command(contractsCommand)
  .command(simulationCommand)
  .command(airdropCommand)
  .demandCommand(1, 'Choose a command from the above list')
  .help().argv
