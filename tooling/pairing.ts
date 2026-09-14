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
      if(mode==='download'){
        const response=await fetch('/download',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({session})});
        if(!response.ok)throw new Error('The transfer has expired. Open a new QR code on your TV.');
        const box=await response.json();const cipher=from64(box.cipher),mac=from64(box.mac),combined=new Uint8Array(cipher.length+mac.length);
        combined.set(cipher);combined.set(mac,cipher.length);
        const plaintext=gcm(key,from64(box.nonce)).decrypt(combined);
        const url=URL.createObjectURL(new Blob([plaintext],{type:'application/octet-stream'}));
        const link=document.createElement('a');link.href=url;link.download='lumen-backup.lumen';link.click();setTimeout(()=>URL.revokeObjectURL(url),10000);
        form.hidden=true;key.fill(0);status.textContent='Backup downloaded. Keep the file and its password safe.';return;
      }
      // getRandomValues is available on HTTP LAN origins; WebCrypto encryption is not.
      const nonce = crypto.getRandomValues(new Uint8Array(12));
      let content:Record<string,unknown>=Object.fromEntries(new FormData(form));
      if(mode==='upload'){
        const file=form.querySelector<HTMLInputElement>('input[type=file]')!.files![0];
        if(file.size>64*1024*1024)throw new Error('Use a backup smaller than 64 MB for QR transfer.');
        content={backup:await file.text()};
      }
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
