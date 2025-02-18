import { loadConfig, patchConfig, saveToAddressBook } from './ignition/ignition'
import { hardhatBaseConfig } from './hardhat.base.config'

const IgnitionHelper = { saveToAddressBook, loadConfig, patchConfig }
export { hardhatBaseConfig, IgnitionHelper }
