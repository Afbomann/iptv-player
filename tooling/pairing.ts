import { gcm } from '@noble/ciphers/aes.js';

const fragment = new URLSearchParams(location.hash.slice(1));
const session = fragment.get('session');
const encoded = fragment.get('key');
const mode=fragment.get('mode');
history.replaceState(null, '', location.pathname);
const form = document.querySelector<HTMLFormElement>('#setup')!;
const status = document.querySelector<HTMLElement>('#status')!;
const from64 = (v: string) => Uint8Array.from(atob(v), c => c.charCodeAt(0));
const to64 = (v: Uint8Array) => {
  let value='';for(let offset=0;offset<v.length;offset+=32768)value+=String.fromCharCode(...v.subarray(offset,offset+32768));return btoa(value);
};
if (!session || !encoded) {
  form.hidden = true;
  status.textContent = 'Scan the QR code displayed by your TV to start a paired session.';
} else {
  const key = from64(encoded);
  if(mode){
    document.querySelector('h1')!.textContent='Take your space with you.';
    form.previousElementSibling!.textContent=mode==='download'?'Download your encrypted device backup.':'Choose an encrypted Lumen backup to restore on your TV.';
    form.innerHTML=mode==='download'?'<button>Download encrypted backup</button>':'<label>Encrypted backup</label><input type="file" accept=".lumen" required><button>Send backup to TV</button>';
  }
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const button = form.querySelector('button')!;
    button.disabled = true;
    try {
      if(mode==='download' || mode==='upload') {
        const limit=256*1024*1024, chunkSize=256*1024;
        const frame=async(path:string,payload:Record<string,unknown>)=>{
          const nonce=crypto.getRandomValues(new Uint8Array(12));
          const cipher=gcm(key,nonce).encrypt(new TextEncoder().encode(JSON.stringify(payload)));
          const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},
            body:JSON.stringify({session,nonce:to64(nonce),cipher:to64(cipher.subarray(0,-16)),mac:to64(cipher.subarray(-16))}),
            signal:AbortSignal.timeout(120000)});
          if(!response.ok)throw new Error(response.status===413?'Backup exceeds the 256 MB limit.':'Transfer interrupted or expired. Scan a new QR code and retry.');
          return response;
        };
        if(mode==='upload') {
          const file=form.querySelector<HTMLInputElement>('input[type=file]')!.files![0];
          if(!file || file.size>limit)throw new Error('Choose a backup no larger than 256 MB.');
          let index=0;
          for(let offset=0;offset<file.size || (offset===0 && file.size===0);offset+=chunkSize) {
            const end=Math.min(offset+chunkSize,file.size);
            const bytes=new Uint8Array(await file.slice(offset,end).arrayBuffer());
            await frame('/backup/upload',{index:index++,bytes:to64(bytes),done:end===file.size});
            status.textContent=`Sending backup: ${Math.round(end/Math.max(1,file.size)*100)}%`;
          }
          form.hidden=true;key.fill(0);status.textContent='Backup sent. Confirm restore on your TV.';
          return;
        }
        const chunks:Uint8Array<ArrayBuffer>[]=[];let total=0;
        for(let index=0;;index++) {
          const response=await frame('/backup/download',{index});
          const box=await response.json(), cipher=from64(box.cipher),mac=from64(box.mac);
          const combined=new Uint8Array(cipher.length+mac.length);combined.set(cipher);combined.set(mac,cipher.length);
          const payload=JSON.parse(new TextDecoder().decode(gcm(key,from64(box.nonce)).decrypt(combined)));
          if(payload.index!==index || typeof payload.done!=='boolean')throw new Error('Invalid transfer frame.');
          const bytes=from64(payload.bytes);total+=bytes.length;
          if(total>limit)throw new Error('Backup exceeds the 256 MB limit.');
          chunks.push(bytes);
          status.textContent=`Downloading backup: ${Math.round(total/Math.max(1,payload.total)*100)}%`;
          if(payload.done)break;
        }
        const url=URL.createObjectURL(new Blob(chunks,{type:'application/octet-stream'}));
        const link=document.createElement('a');link.href=url;link.download='lumen-backup.lumen';link.click();setTimeout(()=>URL.revokeObjectURL(url),10000);
        form.hidden=true;key.fill(0);status.textContent='Backup downloaded. Keep the file and its password safe.';return;
      }
      // getRandomValues is available on HTTP LAN origins; WebCrypto encryption is not.
      const nonce = crypto.getRandomValues(new Uint8Array(12));
      let content:Record<string,unknown>=Object.fromEntries(new FormData(form));

      const payload = new TextEncoder().encode(JSON.stringify(content));
      const cipher = gcm(key, nonce).encrypt(payload);
      const response = await fetch('/submit', {
        method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({session, nonce: to64(nonce), cipher: to64(cipher.slice(0, -16)), mac: to64(cipher.slice(-16))})
      });
      if (!response.ok) throw new Error('Pairing expired or was already used. Open a new QR code on your TV.');
      form.reset(); form.hidden = true; key.fill(0);
      status.textContent = 'Sent. Confirm the playlist on your TV to finish setup.';
    } catch (error) {
      status.textContent = error instanceof Error ? error.message : 'Could not connect to the TV.';
      button.disabled = false;
    }
  });
}
