const CACHE='rokelux-shell-r45';
const SHELL=['./index.html','./manifest.webmanifest','./verificar.html','./verificar-estacion.html','./rename-station.js'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting()));});
self.addEventListener('activate',event=>{event.waitUntil(Promise.all([self.clients.claim(),caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('rokelux-')&&key!==CACHE).map(key=>caches.delete(key))))]));});
self.addEventListener('fetch',event=>{
 const request=event.request,url=new URL(request.url);
 if(request.method!=='GET'||url.origin!==self.location.origin)return;
 if(request.mode==='navigate'){
  event.respondWith(fetch(request).then(async response=>{
   if(!response.ok)return response;
   let html=await response.text();
   if(!html.includes('rename-station.js'))html=html.replace(/<\/body>/i,'<script src="./rename-station.js?v=1"><\/script></body>');
   const headers=new Headers(response.headers);headers.delete('content-length');headers.delete('content-encoding');headers.delete('etag');
   const patched=new Response(html,{status:response.status,statusText:response.statusText,headers});
   caches.open(CACHE).then(cache=>cache.put(request,patched.clone()));return patched;
  }).catch(async()=>await caches.match(request)||await caches.match('./index.html')));
  return;
 }
 if(/\.(?:js|css|png|jpg|jpeg|webp|svg|ico|webmanifest)$/.test(url.pathname))event.respondWith(caches.match(request).then(cached=>cached||fetch(request).then(response=>{if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy));}return response;})));
});
