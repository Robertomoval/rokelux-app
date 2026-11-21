const headers = { "Content-Type": "application/json; charset=utf-8" };
const reply = (status: number, data: unknown) => new Response(JSON.stringify(data), { status, headers });
const esc = (v: unknown) => String(v ?? "").replace(/[&<>"']/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[c]!));
const dateLabel = (s: string) => {
  const a = s.slice(0,10).split("-").map(Number);
  return new Intl.DateTimeFormat("es-EC", { dateStyle:"long", timeZone:"UTC" }).format(new Date(Date.UTC(a[0],a[1]-1,a[2])));
};
async function api(base: string, key: string, path: string, init: RequestInit = {}) {
  return fetch(base + "/rest/v1/" + path, { ...init, headers: { apikey:key, Authorization:"Bearer " + key, "Content-Type":"application/json", ...(init.headers || {}) } });
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return reply(405, { error:"Método no permitido" });
  const token = req.headers.get("x-rokelux-cron-secret") || "";
  if (!token) return reply(401, { error:"No autorizado" });
  const base = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"), resend = Deno.env.get("RESEND_API_KEY");
  if (!base || !key || !resend) return reply(500, { error:"Configuración incompleta" });

  let due: Array<{id:string;service_id:string;reminder_kind:string;due_date:string}>;
  try {
    const r = await api(base,key,"rpc/claim_service_followup_reminders",{method:"POST",body:JSON.stringify({p_token:token,p_limit:50})});
    if (r.status === 401 || r.status === 403) return reply(401,{error:"No autorizado"});
    if (!r.ok) throw new Error("RPC " + r.status + ": " + await r.text());
    due = await r.json();
  } catch (e) { console.error(e); return reply(500,{error:"No se pudieron consultar los recordatorios"}); }

  let sent=0, failed=0;
  for (const item of due) {
    try {
      const r = await api(base,key,"services?select=service_date,service_type,clients(name,email)&id=eq."+encodeURIComponent(item.service_id)+"&limit=1");
      if (!r.ok) throw new Error("Servicio " + r.status);
      const service = (await r.json())[0], client = service && service.clients, email = typeof client?.email === "string" ? client.email.trim() : "";
      if (!email) {
        await api(base,key,"rpc/finish_service_followup_reminder",{method:"POST",body:JSON.stringify({p_id:item.id,p_sent:false,p_error:"FINAL: el cliente no tiene correo registrado"})});
        failed++; continue;
      }
      const month = item.reminder_kind === "1_month", period = month ? "un mes" : "15 días";
      const subject = "Seguimiento de su servicio ROKELUX · " + (month ? "1 mes" : "15 días");
      const html = '<div style="font-family:Arial,sans-serif;max-width:620px;margin:auto;color:#17231a;line-height:1.6">' +
        '<div style="background:#0b1710;padding:22px 26px;border-radius:12px 12px 0 0;color:#fff"><strong style="font-size:22px">ROKE<span style="color:#80ed00">LUX</span></strong><div style="color:#b7c4ba;font-size:12px">Control · Protección · Bienestar</div></div>' +
        '<div style="padding:26px;border:1px solid #dfe8df;border-top:3px solid #80ed00;border-radius:0 0 12px 12px"><p>Hola ' + esc(client.name || "cliente") + ',</p>' +
        '<p>Han transcurrido <strong>' + period + '</strong> desde el servicio de <strong>' + esc(service.service_type || "control de plagas") + '</strong> realizado el ' + esc(dateLabel(service.service_date || item.due_date)) + '.</p>' +
        '<p>Este mensaje es un recordatorio para dar seguimiento al control. Si necesita una nueva revisión o desea comentarnos alguna novedad, responda a este correo.</p>' +
        '<p>Saludos,<br><strong>Equipo ROKELUX</strong><br><a href="mailto:info@rokeluxec.com">info@rokeluxec.com</a></p></div></div>';
      const mail = await fetch("https://api.resend.com/emails",{method:"POST",headers:{Authorization:"Bearer "+resend,"Content-Type":"application/json","Idempotency-Key":"rokelux-service-reminder/"+item.id},body:JSON.stringify({from:"ROKELUX <info@rokeluxec.com>",to:[email],subject,html,reply_to:"info@rokeluxec.com"})});
      const result = await mail.json().catch(()=>({}));
      if (!mail.ok) throw new Error("Resend " + mail.status + ": " + JSON.stringify(result).slice(0,700));
      const done = await api(base,key,"rpc/finish_service_followup_reminder",{method:"POST",body:JSON.stringify({p_id:item.id,p_sent:true,p_email_id:result.id||null})});
      if (!done.ok) throw new Error("Correo enviado; falló el registro " + done.status);
      sent++;
    } catch (e) {
      console.error("Error en recordatorio",item.id,e);
      await api(base,key,"rpc/finish_service_followup_reminder",{method:"POST",body:JSON.stringify({p_id:item.id,p_sent:false,p_error:String(e).slice(0,900)})}).catch(console.error);
      failed++;
    }
  }
  return reply(200,{processed:due.length,sent,failed});
});

