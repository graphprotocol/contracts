// Type augmentation: rocketh's skip() support is enabled via pnpm patch (patches/rocketh@0.17.13.patch).
// Deploy scripts also have early-return guards as a safety net.
import type {
  UnknownDeployments,
  UnresolvedNetworkSpecificData,
  UnresolvedUnknownNamedAccounts,
} from '@rocketh/core/types'

declare module '@rocketh/core/types' {
  interface DeployScriptModule<
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    NamedAccounts extends UnresolvedUnknownNamedAccounts = UnresolvedUnknownNamedAccounts,
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    Data extends UnresolvedNetworkSpecificData = UnresolvedNetworkSpecificData,
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    ArgumentsTypes = undefined,
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    Deployments extends UnknownDeployments = UnknownDeployments,
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    Extra extends Record<string, unknown> = Record<string, unknown>,
  > {
    skip?: () => Promise<boolean>
  }
}
