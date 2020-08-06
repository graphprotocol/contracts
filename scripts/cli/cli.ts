#!/usr/bin/env ts-node
import * as dotenv from 'dotenv'
import yargs from 'yargs'

import { deployCommand } from './commands/deploy'
import { migrateCommand } from './commands/migrate'
import { upgradeCommand } from './commands/upgrade'
import { verifyCommand } from './commands/verify'
import { protocolCommand } from './commands/protocol'
import { cliOpts } from './constants'

dotenv.config()

yargs
  .env(true)
  .option('a', cliOpts.addressBook)
  .option('m', cliOpts.mnemonic)
  .option('p', cliOpts.providerUrl)
  .command(deployCommand)
  .command(migrateCommand)
  .command(upgradeCommand)
  .command(verifyCommand)
  .command(protocolCommand)
  .demandCommand(1, 'Choose a command from the above list')
  .help().argv
