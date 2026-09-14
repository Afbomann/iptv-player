import { join, resolve, extname } from 'node:path';
const root=resolve('build/web');
const port=Number(process.env.PORT??8080);
const mime:Record<string,string>={'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.json':'application/json','.png':'image/png','.ttf':'font/ttf'};
Bun.serve({hostname:'127.0.0.1',port,async fetch(request){
  const url=new URL(request.url);
  if(url.pathname.startsWith('/fixtures/media/')) {
    const name=url.pathname.split('/').pop()!;
    if(!/^[a-zA-Z0-9_.-]+$/.test(name))return new Response('Forbidden',{status:403});
    const authored=['master.m3u8','subtitles.m3u8','english.vtt'].includes(name);
    const file=Bun.file(join(authored?'tooling/fixtures':'.tools/media-fixture',name));
    return await file.exists()?new Response(file,{headers:{'Content-Type':name.endsWith('.m3u8')?'application/vnd.apple.mpegurl':name.endsWith('.vtt')?'text/vtt':'video/mp2t'}}):new Response('Not found',{status:404});
  }
  if(url.pathname==='/fixtures/xtream/player_api.php') {
    const action=url.searchParams.get('action');
    const episode=(id:number,season:number,num:number)=>({id,season,episode_num:num,title:`Episode ${num}`,container_extension:'m3u8',info:{plot:`Season ${season} story`,duration_secs:90}});
    const data:any = !action?{user_info:{auth:1,status:'Active',max_connections:4,active_cons:0}}:
      action==='get_live_categories'?[{category_id:'1',category_name:'News'},{category_id:'2',category_name:'Sport'}]:
      action==='get_vod_categories'?[{category_id:'3',category_name:'Cinema'}]:
      action==='get_series_categories'?[{category_id:'4',category_name:'Drama'}]:
      action==='get_live_streams'?[{stream_id:1,name:'World News',category_id:'1',epg_channel_id:'news',container_extension:'m3u8'},{stream_id:2,name:'Match Day',category_id:'2',container_extension:'m3u8'}]:
      action==='get_vod_streams'?[{stream_id:3,name:'Cinema Only',category_id:'3',container_extension:'m3u8'}]:
      action==='get_series'?[{series_id:4,name:'Drama Only',category_id:'4'}]:
      action==='get_series_info'?{episodes:{'10':[episode(103,10,3)],'2':[episode(22,2,2),episode(21,2,1)]}}:[];
    return Response.json(data);
  }
  if(url.pathname.startsWith('/fixtures/xtream/') && url.pathname.endsWith('.m3u8'))return new Response(Bun.file('tooling/fixtures/master.m3u8'),{headers:{'Content-Type':'application/vnd.apple.mpegurl'}});
  if(url.pathname==='/fixtures/large.m3u') {
    const count=Math.min(50000,Math.max(2,Number(url.searchParams.get('count')??10000)));
    const lines=['#EXTM3U','#EXTINF:-1 tvg-id="news" group-title="News",World News',`http://127.0.0.1:${port}/fixtures/unavailable.ts`];
    for(let i=1;i<count;i++)lines.push(`#EXTINF:-1 group-title="Group ${i%20}",Z Channel ${i}`,`http://127.0.0.1:${port}/fixtures/${i}.ts`);
    return new Response(lines.join('\n'),{headers:{'Content-Type':'text/plain'}});
  }
  if(url.pathname==='/fixtures/playlist.m3u')return new Response('#EXTM3U\n#EXTINF:-1 tvg-id="news" group-title="News",World News\nhttp://127.0.0.1:'+port+'/fixtures/unavailable.ts\n#EXTINF:-1 tvg-id="sport" group-title="Sport",Match Day\nhttp://127.0.0.1:'+port+'/fixtures/unavailable.ts\n',{headers:{'Content-Type':'text/plain'}});
  if(url.pathname==='/fixtures/epg.xml'||url.pathname==='/fixtures/xtream/xmltv.php'){
    const stamp=(date:Date)=>date.toISOString().replace(/[-:TZ.]/g,'').slice(0,14)+' +0000';
    const start=new Date(Date.now()-1800000),end=new Date(Date.now()+3600000);
    return new Response(`<tv><programme channel="news" start="${stamp(start)}" stop="${stamp(end)}"><title>The world this evening</title><desc>Test programme for guide verification.</desc></programme></tv>`,{headers:{'Content-Type':'application/xml'}});
  }
  const path=resolve(join(root,decodeURIComponent(url.pathname)));
  if(path!==root&&!path.startsWith(root+ (process.platform==='win32'?'\\':'/')))return new Response('Forbidden',{status:403});
  const file=Bun.file(path===root?join(root,'index.html'):path);
  if(!await file.exists())return new Response('Not found',{status:404});
  return new Response(file,{headers:{'Content-Type':mime[extname(file.name??'')]??'application/octet-stream','Cache-Control':'no-cache'}});
}});
console.log(`Lumen is available at http://127.0.0.1:${port}`);
