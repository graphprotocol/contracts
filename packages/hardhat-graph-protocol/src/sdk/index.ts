import { loadConfig, patchConfig, saveToAddressBook } from './ignition/ignition'
import { hardhatBaseConfig } from './hardhat.base.config'
import { mergeABIs } from './utils/abi'

const IgnitionHelper = { saveToAddressBook, loadConfig, patchConfig }
export { hardhatBaseConfig, IgnitionHelper, mergeABIs }
