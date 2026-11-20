(()=>{
  if(window.__rokeluxRenameInstalled)return;window.__rokeluxRenameInstalled=true;
  const admin=()=>typeof window.isAdmin==='function'&&window.isAdmin();
  const updateButtons=()=>{
    const list=document.getElementById('stationList');if(!list)return;
    list.querySelectorAll('.station-rename-btn').forEach(b=>b.remove());
    if(!admin())return;
    list.querySelectorAll('.item').forEach(item=>{
      const edit=item.querySelector('button[onclick^="editStation("]');
      const match=edit?.getAttribute('onclick')?.match(/editStation\('([^']+)'\)/);if(!match)return;
      const button=document.createElement('button');button.type='button';button.className='btn ghost station-rename-btn';button.textContent='Renombrar';button.addEventListener('click',()=>window.renameStation(match[1]));item.append(button);
    });
  };
  const original=window.renderStationMap;
  if(typeof original==='function')window.renderStationMap=function(...args){const result=original.apply(this,args);updateButtons();return result;};
  window.renameStation=async id=>{
    if(!admin())return alert('Solo el usuario administrador puede renombrar estaciones.');
    const data=typeof window.state==='function'?window.state():null,station=data?.stations?.find(s=>s.id===id);if(!station)return alert('No se encontró la estación.');
    const value=prompt('Nuevo código de estación:',station.code);if(value===null)return;const code=value.trim();if(!code)return alert('Escribe un código para la estación.');if(code.length>40)return alert('El código no puede superar 40 caracteres.');
    if(data.stations.some(s=>s.clientId===station.clientId&&s.id!==id&&String(s.code).toLocaleLowerCase()===code.toLocaleLowerCase()))return alert('Ya existe otra estación con ese código para este cliente.');
    if(!navigator.onLine)return alert('Conéctate a internet para guardar el cambio.');
    const buttons=document.querySelectorAll('#stationList button');buttons.forEach(b=>b.disabled=true);
    try{const {data:row,error}=await window.sb.from('stations').update({code}).eq('id',id).select('*').single();if(error)throw error;window.cacheStation(row);window.stationMapMessage(station.clientId,'Código actualizado a '+code+'. La ubicación y el historial se conservaron.');}
    catch(error){alert('No se pudo renombrar la estación: '+error.message);}
    finally{buttons.forEach(b=>b.disabled=false);}
  };
  updateButtons();
})();
