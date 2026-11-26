import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

const LIMIT = 5

export async function loadItems(dir) {
  const text = await readFile(join(dir, 'items.json'), 'utf8')
  const rows = JSON.parse(text)
  if (rows.length > LIMIT) {
    return rows.slice(0, LIMIT)
  }
  return rows
}

export function formatItems(rows) {
  return rows.map(row => {
    const label = row.label || 'none'
    return label + ': ' + row.value
  })
}
