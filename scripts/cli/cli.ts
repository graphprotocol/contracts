#!/usr/bin/env ts-node

import yargs from 'yargs'

import { migrateCommand } from './commands/migrate'
import { verifyCommand } from './commands/verify'
import { cliOpts } from './constants'

yargs
  .option('a', cliOpts.addressBook)
  .option('m', cliOpts.mnemonic)
  .option('p', cliOpts.ethProvider)
  .command(migrateCommand)
  .command(verifyCommand)
  .demandCommand(1, 'Choose a command from the above list')
  .help().argv
