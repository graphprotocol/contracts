import fs from 'fs'
import path from 'path'

export function findPathUp(startPath: string, pathToFind: string): string | null {
  let currentDir = path.resolve(startPath)

  while (currentDir !== path.dirname(currentDir)) {
    const candidate = path.join(currentDir, pathToFind)
    if (fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()) {
      return candidate
    }

    const parentDir = path.dirname(currentDir)
    if (parentDir === currentDir) {
      return null
    }

    currentDir = parentDir
  }

  return null
}

export function resolveNodeModulesPath(packageName: string): string {
  const basePath = findPathUp(__dirname, 'node_modules')
  if (!basePath) {
    throw new Error('Could not find node_modules directory')
  }
  return path.resolve(basePath, packageName)
}
