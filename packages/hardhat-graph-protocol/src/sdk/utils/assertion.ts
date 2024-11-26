import { AssertionError } from 'assert'

export function assertObject(
  value: unknown,
  errorMessage?: string,
): asserts value is Record<string, unknown> {
  if (typeof value !== 'object' || value == null)
    throw new AssertionError({
      message: errorMessage ?? 'Not an object',
    })
}
