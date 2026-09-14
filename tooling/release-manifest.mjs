import {createHash, createPrivateKey, sign} from 'node:crypto';
import {createReadStream} from 'node:fs';
import {readFile, writeFile} from 'node:fs/promises';
import {resolve, basename} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function createManifest(config, artifactDirectory, privateKeyPem) {
  if (!Number.isSafeInteger(config.build) || config.build < 1 ||
      !/^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$/.test(config.version)) {
    throw new Error('Use a positive build number and semantic version.');
  }
  const base = new URL(config.baseUrl);
  if (base.protocol !== 'https:' || base.username || base.password || base.search || base.hash || !base.pathname.endsWith('/')) {
    throw new Error('baseUrl must be an HTTPS directory without credentials, query or fragment.');
  }
  const assets = {};
  for (const [platform, name] of Object.entries(config.assets ?? {})) {
    if (!['android','windows','linux','ios','tvos','web'].includes(platform) ||
        typeof name !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(name) || basename(name) !== name) {
      throw new Error('Invalid platform or artifact filename.');
    }
    const hash = createHash('sha256');
    for await (const chunk of createReadStream(resolve(artifactDirectory, name))) hash.update(chunk);
    assets[platform] = {url: new URL(name, base).href, sha256: hash.digest('hex')};
  }
  if (!Object.keys(assets).length) throw new Error('No release assets.');
  const key = createPrivateKey(privateKeyPem);
  if (key.asymmetricKeyType !== 'ed25519') throw new Error('An Ed25519 private key is required.');
  const payload = Buffer.from(JSON.stringify({schema:1, version:config.version, build:config.build, notes:config.notes ?? '', assets}));
  return {payload:payload.toString('base64'), signature:sign(null,payload,key).toString('base64')};
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [configPath, artifacts, output] = process.argv.slice(2);
  if (!configPath || !artifacts || !output || !process.env.LUMEN_RELEASE_PRIVATE_KEY) {
    throw new Error('Usage: node tooling/release-manifest.mjs config.json artifacts/ output.json; set LUMEN_RELEASE_PRIVATE_KEY (PEM) securely.');
  }
  const envelope = await createManifest(JSON.parse(await readFile(configPath,'utf8')), artifacts, process.env.LUMEN_RELEASE_PRIVATE_KEY);
  await writeFile(output, JSON.stringify(envelope), {flag:'wx'});
  console.log('Signed release manifest created. Publish only after verifying the corresponding artifacts.');
}
