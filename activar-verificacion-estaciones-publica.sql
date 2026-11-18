begin;

create or replace function public.rokelux_verify_station(p_station uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
 s public.stations%rowtype;
 payload jsonb:='{}'::jsonb;
 history jsonb:='[]'::jsonb;
 controls jsonb:='[]'::jsonb;
 prefix text:=E'ROKELUX_STATION_V1\n';
begin
 if p_station is null then return jsonb_build_object('valid',false); end if;
 select * into s from public.stations where id=p_station;
 if not found then return jsonb_build_object('valid',false); end if;

 if left(coalesce(s.notes,''),length(prefix))=prefix then
  begin payload:=substring(s.notes from length(prefix)+1)::jsonb;
  exception when others then payload:='{}'::jsonb; end;
 end if;
 history:=payload->'baitHistory';
 if jsonb_typeof(history)='array' then
  select coalesce(jsonb_agg(jsonb_build_object(
   'date',item.value->>'date',
   'status',item.value->>'status',
   'bait_status',item.value->>'baitStatus'
  ) order by item.value->>'date' desc),'[]'::jsonb)
  into controls from jsonb_array_elements(history) as item(value);
 end if;
 if jsonb_array_length(controls)=0 and s.last_check is not null then
  controls:=jsonb_build_array(jsonb_build_object('date',s.last_check,'status',s.status,'bait_status',payload->>'baitStatus'));
 end if;

 return jsonb_build_object(
  'valid',true,
  'station_code',s.code,
  'status',s.status,
  'last_check',s.last_check,
  'controls',controls
 );
end
$$;

revoke all on function public.rokelux_verify_station(uuid) from public;
grant execute on function public.rokelux_verify_station(uuid) to anon,authenticated;

commit;
