#!/usr/bin/env ts-node

import yargs from 'yargs'

import { cliOpts } from './constants'

import { ensCommand } from './commands/ens'
import { migrateCommand } from './commands/migrate'
import { registryCommand } from './commands/registry'

yargs
  .option('a', cliOpts.addressBook)
  .option('m', cliOpts.mnemonic)
  .option('p', cliOpts.ethProvider)
  .command(ensCommand)
  .command(migrateCommand)
  .command(registryCommand)
  .demandCommand(1, 'Choose a command from the above list')
  .help().argv
