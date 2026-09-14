import Hls from 'hls.js';

// The browser backend owns the video and its HLS instance. No global video query:
// every multiview pane has independent track selection and lifetime.
(window as any).lumenVideo = {
  create(notify: () => void) {
    const video = document.createElement('video');
    video.playsInline = true;
    video.controls = false;
    video.style.cssText = 'width:100%;height:100%;object-fit:contain;background:black';
    let hls: Hls | null = null;
    let problem: string | null = null;
    let dead = false;
    const update = () => { if (!dead) notify(); };
    const events = ['playing','pause','waiting','canplay','timeupdate','durationchange','loadedmetadata','volumechange'];
    events.forEach(event => video.addEventListener(event, update));
    video.addEventListener('error', () => { problem = 'This stream cannot be played by the browser. Check its format, CORS permissions, and HTTPS support.'; update(); });
    video.textTracks.addEventListener('change', update);
    video.textTracks.addEventListener('addtrack', update);
    const label = (track: any, index: number) => track.name || track.label || track.lang || track.language || `Track ${index + 1}`;
    return {
      video,
      async open(url: string, headersJson: string, start: number, volume: number) {
        problem = null;
        video.volume = volume;
        video.muted = volume === 0;
        const headers = JSON.parse(headersJson);
        const isHls = /\.m3u8(?:$|[?#])/i.test(url) || new URL(url, location.href).searchParams.get('output') === 'm3u8';
        if (isHls && Hls.isSupported()) {
          hls = new Hls({maxBufferLength: 20, maxMaxBufferLength: 40, backBufferLength: 15,
            xhrSetup: xhr => { for (const [key, value] of Object.entries(headers)) xhr.setRequestHeader(key, String(value)); }});
          hls.on(Hls.Events.ERROR, (_, data) => { if (data.fatal) { problem = 'HLS playback failed. Check the provider and browser access permissions.'; update(); } });
          for (const event of [Hls.Events.AUDIO_TRACKS_UPDATED,Hls.Events.AUDIO_TRACK_SWITCHED,Hls.Events.SUBTITLE_TRACKS_UPDATED,Hls.Events.SUBTITLE_TRACK_SWITCH,Hls.Events.MANIFEST_PARSED]) hls.on(event as any, update);
          await new Promise<void>((resolve, reject) => {
            const timeout = setTimeout(() => reject(new Error('Stream initialization timed out.')), 25000);
            hls!.once(Hls.Events.MANIFEST_PARSED, () => { clearTimeout(timeout); resolve(); });
            hls!.on(Hls.Events.ERROR, (_, data) => { if (data.fatal) { clearTimeout(timeout); reject(new Error('The HLS manifest could not be loaded.')); } });
            hls!.attachMedia(video);
            hls!.loadSource(url);
          });
        } else {
          if (Object.keys(headers).length) throw new Error('This browser cannot attach custom headers to a native media request.');
          video.src = url;
        }
        if (dead) return;
        if (start > 0) video.currentTime = start;
        await video.play();
      },
      state() { return JSON.stringify({playing: !video.paused, buffering: video.readyState < 3,
        position: Number.isFinite(video.currentTime) ? video.currentTime : 0,
        duration: Number.isFinite(video.duration) ? video.duration : 0, error: problem}); },
      tracks() {
        const audio = hls?.audioTracks.length ? hls.audioTracks.map((t, i) => ({id:String(i),label:label(t,i),subtitle:false,selected:hls!.audioTrack === i}))
          : Array.from((video as any).audioTracks || []).map((t:any,i) => ({id:`audio:${i}`,label:label(t,i),subtitle:false,selected:!!t.enabled}));
        const subtitles = hls ? hls.subtitleTracks.map((t,i) => ({id:String(i),label:label(t,i),subtitle:true,selected:hls!.subtitleDisplay && hls!.subtitleTrack === i}))
          : [];
        Array.from(video.textTracks).forEach((t,i) => {
          // HLS subtitle renditions are already listed above. In-band captions
          // and native text tracks are separate and were previously omitted.
          if (!['captions','subtitles'].includes(t.kind)) return;
          if (hls && t.kind !== 'captions' && hls.subtitleTracks.length) return;
          subtitles.push({id:`text:${i}`,label:label(t,i),subtitle:true,selected:t.mode === 'showing'});
        });
        if (subtitles.length) subtitles.unshift({id:'off',label:'Off',subtitle:true,selected:!subtitles.some(t=>t.selected)});
        return JSON.stringify([...audio,...subtitles]);
      },
      async select(id: string, subtitle: boolean) {
        if (id.startsWith('text:') || (subtitle && id === 'off')) {
          const selected = id === 'off' ? -1 : Number(id.slice(5));
          if (hls) { hls.subtitleTrack = -1; hls.subtitleDisplay = false; }
          Array.from(video.textTracks).forEach((t,i) => {
            if (['captions','subtitles'].includes(t.kind)) t.mode = i === selected ? 'showing' : 'disabled';
          });
          update(); return;
        }
        if (id.startsWith('audio:')) {
          const selected = Number(id.slice(6));
          const tracks = (video as any).audioTracks;
          if (!tracks?.[selected]) throw new Error('Audio track is no longer available.');
          for (let i=0;i<tracks.length;i++) tracks[i].enabled = i === selected;
          update(); return;
        }
        const index = id === 'off' ? -1 : Number(id);
        if (hls) {
          if (subtitle) { hls.subtitleDisplay = index >= 0; hls.subtitleTrack = index; }
          else { if (!hls.audioTracks[index]) throw new Error('Audio track is no longer available.'); hls.audioTrack = index; }
        } else if (subtitle) {
          Array.from(video.textTracks).forEach((t,i) => { t.mode = i === index ? 'showing' : 'disabled'; });
        } else {
          const tracks = (video as any).audioTracks;
          if (!tracks?.[index]) throw new Error('This browser does not expose selectable audio tracks for this stream.');
          for (let i=0;i<tracks.length;i++) tracks[i].enabled = i === index;
        }
        update();
      },
      async toggle() { if (video.paused) await video.play(); else video.pause(); },
      seek(seconds: number) {
        if (Number.isFinite(seconds)) {
          video.currentTime = Math.max(0, seconds);
          update(); // Keep subsequent shortcuts in sync before the next timeupdate event.
        }
      },
      volume(value: number) { video.volume = Math.max(0, Math.min(1, value)); video.muted = value === 0; },
      dispose() { dead = true; video.pause(); hls?.destroy(); hls = null; video.removeAttribute('src'); video.load(); video.remove(); },
    };
  },
};
