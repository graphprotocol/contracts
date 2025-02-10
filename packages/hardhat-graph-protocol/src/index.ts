import { extendConfig, extendEnvironment } from 'hardhat/config'
import { greExtendConfig, greExtendEnvironment } from './gre'

// This import is needed to let the TypeScript compiler know that it should include your type
// extensions in your npm package's types file.
import './type-extensions'

// ** Graph Runtime Environment (GRE) extensions for the HRE **
extendConfig(greExtendConfig)
extendEnvironment(greExtendEnvironment)
