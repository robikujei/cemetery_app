-- Optional: after uploading an entrance POINT WKT into
-- public.map_feature_import_staging, run this to set the app's route entrance.
-- The entrance point must be EPSG:4326 WKT, for example:
-- POINT (125.753328125 7.3793125)

alter table public.cemetery_map
  add column if not exists center_lat double precision,
  add column if not exists center_lng double precision,
  add column if not exists lat_span double precision,
  add column if not exists lng_span double precision;

with entrance_point as (
  select
    regexp_match(
      coalesce(nullif(trim(geometry_wkt), ''), nullif(trim(wkt), '')),
      'POINT\s*\(\s*(-?[0-9]+(?:\.[0-9]+)?)\s+(-?[0-9]+(?:\.[0-9]+)?)\s*\)',
      'i'
    ) as match
  from public.map_feature_import_staging
  where nullif(trim(feature_type), '') = 'entrance'
     or coalesce(nullif(trim(geometry_wkt), ''), nullif(trim(wkt), '')) ilike 'POINT%'
  limit 1
),
coords as (
  select
    (match[1])::double precision as lon,
    (match[2])::double precision as lat
  from entrance_point
  where match is not null
),
latest_map_config as (
  select
    map_id,
    coalesce(center_lat, 7.3793125) as center_lat,
    coalesce(center_lng, 125.753328125) as center_lng,
    coalesce(lat_span, 0.0036) as lat_span,
    coalesce(lng_span, 0.0046) as lng_span
  from public.cemetery_map
  order by uploaded_at desc
  limit 1
),
percent as (
  select
    greatest(0, least(100, ((coords.lon - latest_map_config.center_lng) / latest_map_config.lng_span + 0.5) * 100))
      as entrance_x_percent,
    greatest(0, least(100, (0.5 - (coords.lat - latest_map_config.center_lat) / latest_map_config.lat_span) * 100))
      as entrance_y_percent
  from coords
  cross join latest_map_config
),
latest_map as (
  select map_id
  from public.cemetery_map
  order by uploaded_at desc
  limit 1
),
updated as (
  update public.cemetery_map map
  set
    entrance_x_percent = percent.entrance_x_percent,
    entrance_y_percent = percent.entrance_y_percent
  from percent, latest_map
  where map.map_id = latest_map.map_id
  returning map.map_id
)
insert into public.cemetery_map (
  map_image_url,
  entrance_x_percent,
  entrance_y_percent,
  uploaded_at
)
select
  null,
  percent.entrance_x_percent,
  percent.entrance_y_percent,
  now()
from percent
where not exists (select 1 from updated);
