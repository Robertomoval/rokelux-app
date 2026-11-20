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
 prefix text:=E'ROKELUX_STATION_V1\\n';
begin
 if p_station is null then return jsonb_build_object('valid',false); end if;
 select * into s from public.stations where id=p_station;
 if not found then return jsonb_build_object('valid',false); end if;

 if left(coalesce(s.notes,''),length(prefix))=prefix then
  begin payload:=substring(s.notes from length(prefix)+1)::jsonb;
  exception when others then payload:='{}'::jsonb; end;
 end if;
 history:=payload->'baitHistory';
 with source_rows as (
  select r.id::text as control_key,r.reviewed_at as occurred_at,r.status,r.bait_status,0 as priority
  from public.rokelux_station_reviews r where r.station_id=s.id
  union all
  select coalesce(nullif(item.value->>'reviewId',''),'legacy:'||(item.value->>'date')||'|'||(item.value->>'status')||'|'||(item.value->>'baitStatus')),
   (item.value->>'date')::timestamptz,item.value->>'status',item.value->>'baitStatus',1
  from jsonb_array_elements(case when jsonb_typeof(history)='array' then history else '[]'::jsonb end) as item(value)
  where coalesce(item.value->>'date','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
 ), dedup as (
  select distinct on (control_key) control_key,occurred_at,status,bait_status
  from source_rows order by control_key,priority,occurred_at desc
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'date',occurred_at,
  'status',status,
  'bait_status',bait_status
 ) order by occurred_at desc),'[]'::jsonb)
 into controls from dedup;
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
