import { loadConfig, mergeConfigs, patchConfig, saveAddressBook } from './ignition/ignition'
import { hardhatBaseConfig } from './hardhat.base.config'

const IgnitionHelper = { saveAddressBook, loadConfig, patchConfig, mergeConfigs }
export { hardhatBaseConfig, IgnitionHelper }
