#!/usr/bin/env ts-node

import yargs from 'yargs'

import { migrateCommand } from './commands/migrate'

yargs
  .command(migrateCommand)
  .demandCommand(1, 'Choose a command from the above list')
  .help().argv
