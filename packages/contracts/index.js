// Entry point for @graphprotocol/contracts package
// Exports the address book directory path for easy resolution

const path = require('path')

module.exports = {
  // Directory where address book files are located
  addressBookDir: __dirname,
  // Directory where artifacts are located
  artifactsDir: path.join(__dirname, 'artifacts'),
}
