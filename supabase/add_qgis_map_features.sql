-- Run this once before importing QGIS map layers, blocks, pathways, entrances,
-- or boundaries.
-- Export each QGIS layer as CSV with geometry as WKT in EPSG:4326.

create table if not exists public.cemetery_map_features (
  feature_id bigserial primary key,
  feature_type text not null,
  feature_name text,
  geometry_wkt text not null,
  stroke_color text,
  fill_color text,
  stroke_width numeric,
  sort_order integer not null default 100,
  is_visible boolean not null default true,
  source_feature_id text,
  created_at timestamptz not null default now()
);

create index if not exists cemetery_map_features_type_idx
  on public.cemetery_map_features (feature_type);

create index if not exists cemetery_map_features_visible_idx
  on public.cemetery_map_features (is_visible, sort_order);

-- Staging table for Supabase CSV import from QGIS.
-- Use feature_type = map_layer for the cemetery line-art/base-map drawing.
-- Rename the exported WKT column to geometry_wkt before uploading.
create table if not exists public.map_feature_import_staging (
  feature_type text,
  feature_name text,
  name text,
  block_number text,
  fid text,
  qgis_feature_id text,
  geometry_wkt text,
  wkt text,
  stroke_color text,
  fill_color text,
  stroke_width numeric,
  sort_order integer,
  is_visible boolean
);

alter table public.map_feature_import_staging
  add column if not exists feature_type text,
  add column if not exists feature_name text,
  add column if not exists name text,
  add column if not exists block_number text,
  add column if not exists fid text,
  add column if not exists qgis_feature_id text,
  add column if not exists geometry_wkt text,
  add column if not exists wkt text,
  add column if not exists stroke_color text,
  add column if not exists fill_color text,
  add column if not exists stroke_width numeric,
  add column if not exists sort_order integer,
  add column if not exists is_visible boolean;
