(()=>{
      const menu=document.getElementById('menuToggle'),nav=document.getElementById('navlinks');
      menu.addEventListener('click',()=>{const open=nav.classList.toggle('open');menu.setAttribute('aria-expanded',String(open));menu.setAttribute('aria-label',open?'Cerrar menú':'Abrir menú')});
      nav.querySelectorAll('a').forEach(a=>a.addEventListener('click',()=>{nav.classList.remove('open');menu.setAttribute('aria-expanded','false');menu.setAttribute('aria-label','Abrir menú')}));
      document.getElementById('year').textContent=new Date().getFullYear();
      const form=document.getElementById('quoteForm'),error=document.getElementById('formError');
      form.addEventListener('submit',event=>{
        event.preventDefault();
        if(!form.reportValidity())return;
        const data=new FormData(form),v=k=>String(data.get(k)||'').trim();
        const lines=['Hola ROKELUX, deseo solicitar una cotización.','',`Nombre: ${v('name')}`,`Empresa: ${v('company')||'No indicada'}`,`Teléfono: ${v('phone')}`,`Correo: ${v('email')||'No indicado'}`,`Servicio: ${v('service')}`,`Detalle: ${v('message')||'Quisiera recibir orientación.'}`];
        const url=`https://wa.me/593994981292?text=${encodeURIComponent(lines.join('\n'))}`;
        const popup=window.open(url,'_blank');
        if(popup){popup.opener=null;}else{window.location.href=url;return;}
        error.style.display='none';
      });
      form.addEventListener('invalid',()=>{error.style.display='block'},true);
    })();