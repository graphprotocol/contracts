import { loadConfig, mergeConfigs, patchConfig, saveToAddressBook } from './ignition/ignition'
import { hardhatBaseConfig } from './hardhat.base.config'

const IgnitionHelper = { saveToAddressBook, loadConfig, patchConfig, mergeConfigs }
export { hardhatBaseConfig, IgnitionHelper }
