import { copyFile, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = process.cwd();
const dist = resolve(root, 'dist');
const distAssets = resolve(dist, 'assets');
const publishedAssets = resolve(root, 'assets');

const builtHtml = await readFile(resolve(dist, 'index.html'), 'utf8');
await writeFile(resolve(root, 'index.html'), builtHtml.replace(/\r\n/g, '\n'));
await mkdir(publishedAssets, { recursive: true });

for (const entry of await readdir(distAssets, { withFileTypes: true })) {
  if (!entry.isFile()) {
    throw new Error(`Unexpected build output in assets: ${entry.name}`);
  }

  await copyFile(resolve(distAssets, entry.name), resolve(publishedAssets, entry.name));
}

console.log('GitHub Pages files copied to the repository root.');
