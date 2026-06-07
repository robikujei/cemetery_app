-- Run this in Supabase SQL Editor before importing QGIS lot data.
-- Adds QGIS-friendly attributes to the existing cemetery_lot table.

alter table public.cemetery_lot
  add column if not exists block_number text,
  add column if not exists lot_class_type text,
  add column if not exists lot_label text,
  add column if not exists qgis_feature_id text,
  add column if not exists polygon_geo jsonb;

alter table public.cemetery_map
  add column if not exists center_lat double precision,
  add column if not exists center_lng double precision,
  add column if not exists lat_span double precision,
  add column if not exists lng_span double precision;

update public.cemetery_lot
set lot_label = lot_number
where lot_label is null
  and lot_number is not null;

create index if not exists cemetery_lot_block_number_idx
  on public.cemetery_lot (block_number);

create index if not exists cemetery_lot_lot_label_idx
  on public.cemetery_lot (lot_label);

create index if not exists cemetery_lot_qgis_feature_id_idx
  on public.cemetery_lot (qgis_feature_id)
  where qgis_feature_id is not null;

-- Optional staging table for a partial QGIS CSV import.
-- Accepted coordinate columns:
-- - App-friendly: qgis_feature_id, lon, lat
-- - QGIS geometry attributes: fid, xcoord, ycoord
-- - Some QGIS exports: fid, x, y
create table if not exists public.lot_import_staging (
  qgis_feature_id text,
  fid text,
  block_number text,
  lot_number text,
  lot_label text,
  lot_class_type text,
  price numeric,
  status text,
  lon double precision,
  lat double precision,
  xcoord text,
  ycoord text,
  x text,
  y text,
  polygon_geo jsonb
);

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
