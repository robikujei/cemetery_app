-- After uploading a QGIS WKT CSV into public.map_feature_import_staging,
-- run this to copy the staged features into the visible app map layer.
--
-- Change default_feature_type for each import:
-- map_layer, boundary, block, pathway, entrance, or other.
-- If the QGIS layer is named maplayer, keep the app feature_type as map_layer.
--
-- Set replace_existing_for_type to true when you want this import to replace
-- the old features of the same type.
--
-- Keep force_default_feature_type true only when the staging table contains one
-- QGIS layer export. For the cemetery line-art/base-map layer named maplayer,
-- this makes every staged row become app feature_type map_layer.
--
-- If staging contains multiple QGIS layers/features at once, set
-- force_default_feature_type to false and make sure the staged feature_type
-- column identifies each row as map_layer, boundary, block, pathway, entrance,
-- or other.

with import_options as (
  select
    'map_layer'::text as default_feature_type,
    true::boolean as replace_existing_for_type,
    false::boolean as force_default_feature_type
),
settings as (
  select
    case
      when lower(regexp_replace(trim(default_feature_type), '[[:space:]_-]+', '', 'g')) = 'maplayer'
        then 'map_layer'
      else lower(regexp_replace(trim(default_feature_type), '[[:space:]-]+', '_', 'g'))
    end as default_feature_type,
    replace_existing_for_type,
    force_default_feature_type
  from import_options
),
deleted as (
  delete from public.cemetery_map_features feature
  using settings
  where settings.replace_existing_for_type
    and (
      case
        when lower(regexp_replace(trim(feature.feature_type), '[[:space:]_-]+', '', 'g')) = 'maplayer'
          then 'map_layer'
        else lower(regexp_replace(trim(feature.feature_type), '[[:space:]-]+', '_', 'g'))
      end
    ) = settings.default_feature_type
  returning feature.feature_id
),
raw_source as (
  select
    case
      when settings.force_default_feature_type
        then settings.default_feature_type
      else coalesce(nullif(trim(feature_type), ''), settings.default_feature_type)
    end as raw_feature_type,
    coalesce(
      nullif(trim(feature_name), ''),
      nullif(trim(name), ''),
      nullif(trim(block_number), ''),
      nullif(trim(qgis_feature_id), ''),
      nullif(trim(fid), '')
    ) as feature_name,
    coalesce(
      nullif(trim(qgis_feature_id), ''),
      nullif(trim(fid), '')
    ) as source_feature_id,
    coalesce(
      nullif(trim(geometry_wkt), ''),
      nullif(trim(wkt), '')
    ) as geometry_wkt,
    nullif(trim(stroke_color), '') as stroke_color,
    nullif(trim(fill_color), '') as fill_color,
    stroke_width,
    coalesce(
      sort_order,
      case
        when settings.default_feature_type = 'map_layer' then 10
        else 100
      end
    ) as sort_order,
    coalesce(is_visible, true) as is_visible
  from public.map_feature_import_staging
  cross join settings
),
source as (
  select
    case
      when lower(regexp_replace(trim(raw_feature_type), '[[:space:]_-]+', '', 'g')) = 'maplayer'
        then 'map_layer'
      else lower(regexp_replace(trim(raw_feature_type), '[[:space:]-]+', '_', 'g'))
    end as feature_type,
    feature_name,
    source_feature_id,
    geometry_wkt,
    stroke_color,
    fill_color,
    stroke_width,
    sort_order,
    is_visible
  from raw_source
),
inserted as (
  insert into public.cemetery_map_features (
    feature_type,
    feature_name,
    geometry_wkt,
    stroke_color,
    fill_color,
    stroke_width,
    sort_order,
    is_visible,
    source_feature_id
  )
  select
    feature_type,
    feature_name,
    geometry_wkt,
    stroke_color,
    fill_color,
    stroke_width,
    sort_order,
    is_visible,
    source_feature_id
  from source
  where geometry_wkt is not null
  returning feature_id, feature_type
)
select
  (select count(*) from public.map_feature_import_staging) as staging_rows,
  (select count(*) from source where geometry_wkt is not null) as valid_geometry_rows,
  (select count(*) from deleted) as deleted_existing_rows,
  (select count(*) from inserted) as inserted_rows,
  (select count(*) from inserted where feature_type = 'map_layer') as inserted_map_layer_rows,
  (
    select count(*)
    from public.cemetery_map_features
    where is_visible
      and (
        case
          when lower(regexp_replace(trim(feature_type), '[[:space:]_-]+', '', 'g')) = 'maplayer'
            then 'map_layer'
          else lower(regexp_replace(trim(feature_type), '[[:space:]-]+', '_', 'g'))
        end
      ) = 'map_layer'
  ) as visible_map_layer_rows;
