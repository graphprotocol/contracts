import { loadConfig, saveAddressBook } from './ignition/ignition'
import { hardhatBaseConfig } from './hardhat.base.config'

const IgnitionHelper = { saveAddressBook, loadConfig }
export { hardhatBaseConfig, IgnitionHelper }
