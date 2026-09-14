import {readdir,mkdir,copyFile,writeFile,readFile} from 'node:fs/promises';
import {join,basename} from 'node:path';
import {createPrivateKey,createPublicKey,verify,createHash} from 'node:crypto';
import {createManifest} from './release-manifest.mjs';

const version=process.env.RELEASE_VERSION,build=Number(process.env.RELEASE_BUILD);
if (!/^\d+\.\d+\.\d+$/.test(version??'') || !Number.isSafeInteger(build) || build<1) throw new Error('Invalid release version/build');
const privateKey=process.env.LUMEN_RELEASE_PRIVATE_KEY;
const publicKey=createPublicKey(createPrivateKey(privateKey));
if(publicKey.asymmetricKeyType!=='ed25519')throw new Error('Expected Ed25519 signing key');
const rawPublic=Buffer.from(publicKey.export({format:'jwk'}).x,'base64url');
if(!rawPublic.equals(Buffer.from(process.env.LUMEN_UPDATE_PUBLIC_KEY??'','base64')))throw new Error('Private key does not match the public key embedded in the app');

// Do not accidentally publish an older build as the latest update.
const previous=await fetch('https://github.com/Afbomann/iptv-player/releases/latest/download/updates.json',{signal:AbortSignal.timeout(30000)});
if(previous.ok){
  const envelope=await previous.json();
  const payload=Buffer.from(envelope.payload,'base64');
  if(!verify(null,payload,publicKey,Buffer.from(envelope.signature,'base64')))throw new Error('Previous release does not verify with this signing key');
  if(JSON.parse(payload).build>=build)throw new Error('Build number must exceed the currently published build');
} else if(previous.status!==404)throw new Error(`Cannot check previous release: HTTP ${previous.status}`);

async function files(directory){
  const result=[];
  for(const entry of await readdir(directory,{withFileTypes:true})){
    const path=join(directory,entry.name);
    if(entry.isDirectory())result.push(...await files(path));
    else if(entry.isFile())result.push(path);
  }
  return result;
}
const candidates=await files('release-artifacts');
const assets={android:'lumen-android.apk',windows:'lumen-windows-x64-setup.exe',linux:'lumen-linux-amd64.deb'};
const original={android:'app-release.apk',windows:assets.windows,linux:assets.linux};
await mkdir('release-output');
for(const platform of Object.keys(assets)){
  const matches=candidates.filter(path=>basename(path)===original[platform]);
  if(matches.length!==1)throw new Error(`Expected exactly one ${platform} installer, found ${matches.length}`);
  await copyFile(matches[0],join('release-output',assets[platform]));
}
const notes=`Lumen ${version} (build ${build}).\n\nDirect downloads only: Android/Android TV/Fire TV APK; Windows x64 installer; Ubuntu 24.04+ amd64 .deb.\n\nWindows installer is not Authenticode-signed and may display SmartScreen warnings. Native device acceptance testing is required before production use. Back up your library before upgrading.\n`;
const config={version,build,notes,baseUrl:`https://github.com/Afbomann/iptv-player/releases/download/v${version}/`,assets};
const envelope=await createManifest(config,'release-output',privateKey);
await writeFile('release-output/updates.json',JSON.stringify(envelope));
await writeFile('release-output/notes.md',notes);
const sums=[];
for(const name of [...Object.values(assets),'updates.json'])sums.push(`${createHash('sha256').update(await readFile(join('release-output',name))).digest('hex')}  ${name}`);
await writeFile('release-output/SHA256SUMS',sums.join('\n')+'\n');
console.log('Three installers and signed metadata are ready for the GitHub release.');
