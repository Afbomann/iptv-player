import {readFile, appendFile} from 'node:fs/promises';
import {createPublicKey, verify} from 'node:crypto';
import {pathToFileURL} from 'node:url';

function parts(version) {
  if (!/^\d+\.\d+\.\d+$/.test(version ?? '')) throw new Error('Invalid semantic version');
  const values = version.split('.').map(Number);
  if (values.some(value => !Number.isSafeInteger(value) || value > 65535)) throw new Error('Version exceeds installer limits');
  return values;
}

export function resolveVersion({event, run, pubspec, version, build, previous}) {
  if (event === 'push') {
    const match = /^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m.exec(pubspec);
    if (!match || !Number.isSafeInteger(run) || run < 1) throw new Error('Invalid pubspec version or run number');
    let [major, minor, patch] = parts(match[1]);
    patch += run;
    if (previous) {
      const prior = parts(previous.version);
      const candidate = [major, minor, patch];
      const difference = candidate.map((value, index) => value - prior[index]).find(value => value !== 0) ?? 0;
      if (difference <= 0) [major, minor, patch] = [prior[0], prior[1], prior[2] + 1];
    }
    version = `${major}.${minor}.${patch}`;
    build = Math.max(Number(match[2]) + run, (previous?.build ?? 0) + 1);
  } else if (event !== 'workflow_dispatch') {
    throw new Error('Unsupported release event');
  }
  parts(version);
  build = Number(build);
  if (!Number.isSafeInteger(build) || build < 1 || build > 2100000000) throw new Error('Invalid Android build number');
  return {version, build};
}

async function main() {
  let previous;
  if (process.env.RELEASE_EVENT === 'push') {
    const response = await fetch('https://github.com/Afbomann/iptv-player/releases/latest/download/updates.json', {signal: AbortSignal.timeout(30000)});
    if (response.ok) {
      const envelope = await response.json();
      const raw = Buffer.from(process.env.LUMEN_UPDATE_PUBLIC_KEY ?? '', 'base64');
      if (raw.length !== 32) throw new Error('Set LUMEN_UPDATE_PUBLIC_KEY');
      const key = createPublicKey({key: {kty: 'OKP', crv: 'Ed25519', x: raw.toString('base64url')}, format: 'jwk'});
      const payload = Buffer.from(envelope.payload, 'base64');
      if (!verify(null, payload, key, Buffer.from(envelope.signature, 'base64'))) throw new Error('Previous release signature is invalid');
      previous = JSON.parse(payload);
      if (!Number.isSafeInteger(previous.build) || previous.build < 1) throw new Error('Invalid previous build');
    } else if (response.status !== 404) throw new Error(`Cannot read previous release: HTTP ${response.status}`);
  }
  const result = resolveVersion({event: process.env.RELEASE_EVENT, run: Number(process.env.RELEASE_RUN),
    pubspec: await readFile('pubspec.yaml', 'utf8'), version: process.env.RELEASE_VERSION,
    build: process.env.RELEASE_BUILD, previous});
  await appendFile(process.env.GITHUB_OUTPUT, `version=${result.version}\nbuild=${result.build}\n`);
  console.log(`Release ${result.version}, build ${result.build}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
