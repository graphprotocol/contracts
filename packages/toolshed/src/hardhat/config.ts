/* eslint-disable @typescript-eslint/no-unsafe-assignment */
/* eslint-disable @typescript-eslint/no-unsafe-call */
import { existsSync } from 'fs'
import { globSync } from 'glob'
import { join } from 'path'

export function loadTasks(rootPath: string) {
  const tasksPath = join(rootPath, 'tasks')
  const files: string[] = globSync('**/*.ts', { cwd: tasksPath, absolute: true })
  files.forEach(require)
}

// This is going to fail if the project is using a different build directory
export function isProjectBuilt(rootPath: string) {
  return existsSync(join(rootPath, 'build/contracts'))
}
