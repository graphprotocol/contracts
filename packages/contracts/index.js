// Entry point for @graphprotocol/contracts package
// Exports the address book directory path for easy resolution

const path = require('path')

module.exports = {
  // Directory where address book files are located
  addressBookDir: __dirname,
  // Directory where config files are located
  configDir: path.join(__dirname, 'config'),
  // Directory where artifacts are located
  artifactsDir: path.join(__dirname, 'artifacts'),
}
