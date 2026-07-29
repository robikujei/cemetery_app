-- After loading a QGIS centroid CSV into public.lot_import_staging,
-- run this to partially import lots into the app's current tables.
--
-- Accepted staging coordinate columns:
-- qgis_feature_id, lon, lat
-- or QGIS defaults: fid, xcoord, ycoord
-- or QGIS variants: fid, x, y

alter table public.lot_import_staging
  add column if not exists qgis_feature_id text,
  add column if not exists fid text,
  add column if not exists block_number text,
  add column if not exists lot_number text,
  add column if not exists lot_label text,
  add column if not exists lot_class_type text,
  add column if not exists price numeric,
  add column if not exists status text,
  add column if not exists lon double precision,
  add column if not exists lat double precision,
  add column if not exists xcoord text,
  add column if not exists ycoord text,
  add column if not exists x text,
  add column if not exists y text,
  add column if not exists polygon_geo jsonb;

alter table public.cemetery_map
  add column if not exists center_lat double precision,
  add column if not exists center_lng double precision,
  add column if not exists lat_span double precision,
  add column if not exists lng_span double precision;

-- The current QGIS/vector map does not require a raster image or physical
-- raster dimensions. Older database versions made these columns mandatory,
-- which prevents creation of a new map configuration after a data purge.
alter table public.cemetery_map
  alter column map_image_url drop not null,
  alter column map_width_meters drop not null,
  alter column map_height_meters drop not null;

with normalized as (
  select
    qgis_feature_id,
    fid,
    block_number,
    lot_number,
    lot_label,
    lot_class_type,
    price,
    status,
    coalesce(
      nullif(trim(lon::text), ''),
      nullif(trim(xcoord), ''),
      nullif(trim(x), '')
    ) as lon_text,
    coalesce(
      nullif(trim(lat::text), ''),
      nullif(trim(ycoord), ''),
      nullif(trim(y), '')
    ) as lat_text,
    polygon_geo
  from public.lot_import_staging
),
numbered as (
  select
    *,
    row_number() over (
      order by lat_text::double precision, lon_text::double precision
    ) as import_row_number
  from normalized
  where lon_text ~ '^-?([0-9]+(\.[0-9]*)?|\.[0-9]+)$'
    and lat_text ~ '^-?([0-9]+(\.[0-9]*)?|\.[0-9]+)$'
),
source_base as (
  select
    coalesce(
      nullif(trim(qgis_feature_id), ''),
      nullif(trim(fid), ''),
      'staging-' || import_row_number
    ) as qgis_feature_id,
    nullif(trim(block_number), '') as block_number,
    coalesce(
      nullif(trim(lot_number), ''),
      'UNMAPPED-' || lpad(
        import_row_number::text,
        3,
        '0'
      )
    ) as lot_number,
    coalesce(
      nullif(trim(lot_label), ''),
      case
        when nullif(trim(block_number), '') is not null
          and nullif(trim(lot_number), '') is not null
          then trim(block_number) || '-' || trim(lot_number)
        else null
      end
      ,
      'Unmapped Lot ' || lpad(
        import_row_number::text,
        3,
        '0'
      )
    ) as lot_label,
    nullif(trim(lot_class_type), '') as lot_class_type,
    coalesce(price, 0) as price,
    coalesce(nullif(trim(status), ''), 'Available') as status,
    lon_text::double precision as lon,
    lat_text::double precision as lat,
    polygon_geo
  from numbered
),
bounds as (
  select
    (min(lat) + max(lat)) / 2 as center_lat,
    (min(lon) + max(lon)) / 2 as center_lng,
    greatest((max(lat) - min(lat)) * 1.2, 0.0012) as lat_span,
    greatest((max(lon) - min(lon)) * 1.2, 0.0012) as lng_span
  from source_base
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
source as (
  select
    source_base.*,
    greatest(
      0,
      least(100, ((source_base.lon - bounds.center_lng) / bounds.lng_span + 0.5) * 100)
    ) as x_percent,
    greatest(
      0,
      least(100, (0.5 - (source_base.lat - bounds.center_lat) / bounds.lat_span) * 100)
    ) as y_percent
  from source_base
  cross join bounds
),
updated_lots as (
  update public.cemetery_lot lot
  set
    block_number = source.block_number,
    lot_number = source.lot_number,
    lot_label = source.lot_label,
    lot_class_type = source.lot_class_type,
    qgis_feature_id = source.qgis_feature_id,
    polygon_geo = source.polygon_geo,
    price = source.price,
    status = source.status,
    x_coord = source.lon,
    y_coord = source.lat
  from source
  where (
      source.qgis_feature_id is not null
      and lot.qgis_feature_id = source.qgis_feature_id
    )
    or (
      source.qgis_feature_id is null
      and lot.lot_label = source.lot_label
    )
  returning
    lot.lot_id,
    source.qgis_feature_id,
    source.lot_label,
    source.x_percent,
    source.y_percent
),
inserted_lots as (
  insert into public.cemetery_lot (
    block_number,
    lot_number,
    lot_label,
    lot_class_type,
    qgis_feature_id,
    polygon_geo,
    price,
    status,
    x_coord,
    y_coord
  )
  select
    source.block_number,
    source.lot_number,
    source.lot_label,
    source.lot_class_type,
    source.qgis_feature_id,
    source.polygon_geo,
    source.price,
    source.status,
    source.lon,
    source.lat
  from source
  where not exists (
    select 1
    from public.cemetery_lot lot
    where (
        source.qgis_feature_id is not null
        and lot.qgis_feature_id = source.qgis_feature_id
      )
      or (
        source.qgis_feature_id is null
        and lot.lot_label = source.lot_label
      )
  )
  returning lot_id, qgis_feature_id, lot_label
),
matched_lots as (
  select
    updated_lots.lot_id,
    updated_lots.x_percent,
    updated_lots.y_percent
  from updated_lots
  union all
  select
    inserted_lots.lot_id,
    source.x_percent,
    source.y_percent
  from inserted_lots
  join source
    on source.qgis_feature_id = inserted_lots.qgis_feature_id
    or (
      source.qgis_feature_id is null
      and source.lot_label = inserted_lots.lot_label
    )
),
updated_markers as (
  update public.lot_markers marker
  set
    x_percent = matched_lots.x_percent,
    y_percent = matched_lots.y_percent
  from matched_lots
  where marker.lot_id = matched_lots.lot_id
  returning marker.lot_id
),
inserted_markers as (
  insert into public.lot_markers (lot_id, x_percent, y_percent)
  select matched_lots.lot_id, matched_lots.x_percent, matched_lots.y_percent
  from matched_lots
  where not exists (
    select 1
    from public.lot_markers marker
    where marker.lot_id = matched_lots.lot_id
  )
  returning lot_id
)
select
  (select count(*) from public.lot_import_staging) as staging_rows,
  (select count(*) from source) as valid_coordinate_rows,
  (select count(*) from updated_lots) as updated_lots,
  (select count(*) from inserted_lots) as inserted_lots,
  (select count(*) from updated_markers) as updated_markers,
  (select count(*) from inserted_markers) as inserted_markers,
  (select center_lat from bounds) as map_center_lat,
  (select center_lng from bounds) as map_center_lng,
  (select lat_span from bounds) as map_lat_span,
  (select lng_span from bounds) as map_lng_span,
  (select count(*) from updated_map) as updated_map_rows,
  (select count(*) from inserted_map) as inserted_map_rows;
