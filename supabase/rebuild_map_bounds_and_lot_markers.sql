-- Use this if lots were already imported while the map still pointed
-- at the old hardcoded center. It rebuilds the active map bounds and
-- lot marker percentages from cemetery_lot.x_coord/y_coord.

alter table public.cemetery_map
  add column if not exists center_lat double precision,
  add column if not exists center_lng double precision,
  add column if not exists lat_span double precision,
  add column if not exists lng_span double precision;

with source as (
  select
    lot_id,
    x_coord::double precision as lon,
    y_coord::double precision as lat
  from public.cemetery_lot
  where x_coord is not null
    and y_coord is not null
),
bounds as (
  select
    (min(lat) + max(lat)) / 2 as center_lat,
    (min(lon) + max(lon)) / 2 as center_lng,
    greatest((max(lat) - min(lat)) * 1.2, 0.0012) as lat_span,
    greatest((max(lon) - min(lon)) * 1.2, 0.0012) as lng_span
  from source
),
latest_map as (
  select map_id
  from public.cemetery_map
  order by uploaded_at desc
  limit 1
),
updated_map as (
  update public.cemetery_map map
  set
    center_lat = bounds.center_lat,
    center_lng = bounds.center_lng,
    lat_span = bounds.lat_span,
    lng_span = bounds.lng_span
  from bounds, latest_map
  where map.map_id = latest_map.map_id
    and bounds.center_lat is not null
    and bounds.center_lng is not null
  returning map.map_id
),
inserted_map as (
  insert into public.cemetery_map (
    map_image_url,
    center_lat,
    center_lng,
    lat_span,
    lng_span,
    uploaded_at
  )
  select
    null,
    bounds.center_lat,
    bounds.center_lng,
    bounds.lat_span,
    bounds.lng_span,
    now()
  from bounds
  where bounds.center_lat is not null
    and bounds.center_lng is not null
    and not exists (select 1 from updated_map)
  returning map_id
),
positioned as (
  select
    source.lot_id,
    greatest(
      0,
      least(100, ((source.lon - bounds.center_lng) / bounds.lng_span + 0.5) * 100)
    ) as x_percent,
    greatest(
      0,
      least(100, (0.5 - (source.lat - bounds.center_lat) / bounds.lat_span) * 100)
    ) as y_percent
  from source
  cross join bounds
),
updated_markers as (
  update public.lot_markers marker
  set
    x_percent = positioned.x_percent,
    y_percent = positioned.y_percent
  from positioned
  where marker.lot_id = positioned.lot_id
  returning marker.lot_id
),
inserted_markers as (
  insert into public.lot_markers (lot_id, x_percent, y_percent)
  select positioned.lot_id, positioned.x_percent, positioned.y_percent
  from positioned
  where not exists (
    select 1
    from public.lot_markers marker
    where marker.lot_id = positioned.lot_id
  )
  returning lot_id
)
select
  (select count(*) from source) as lots_with_coordinates,
  (select count(*) from updated_markers) as updated_markers,
  (select count(*) from inserted_markers) as inserted_markers,
  (select center_lat from bounds) as map_center_lat,
  (select center_lng from bounds) as map_center_lng,
  (select lat_span from bounds) as map_lat_span,
  (select lng_span from bounds) as map_lng_span,
  (select count(*) from updated_map) as updated_map_rows,
  (select count(*) from inserted_map) as inserted_map_rows;
