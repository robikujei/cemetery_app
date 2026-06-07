import argparse
import csv
import json
from pathlib import Path


MAP_FEATURE_FIELDS = [
    "feature_type",
    "feature_name",
    "name",
    "block_number",
    "fid",
    "qgis_feature_id",
    "geometry_wkt",
    "wkt",
    "stroke_color",
    "fill_color",
    "stroke_width",
    "sort_order",
    "is_visible",
]

LOT_FIELDS = [
    "qgis_feature_id",
    "block_number",
    "lot_number",
    "lot_label",
    "lot_class_type",
    "price",
    "status",
    "lon",
    "lat",
    "polygon_geo",
]


def main():
    parser = argparse.ArgumentParser(
        description="Convert a QGIS GeoJSON export into a Supabase import CSV.",
    )
    parser.add_argument("input", help="Path to the GeoJSON file exported from QGIS.")
    parser.add_argument("output", help="Path to write the CSV file.")
    parser.add_argument(
        "--mode",
        choices=["map-feature", "lots"],
        required=True,
        help="Use map-feature for blocks/pathways/boundary/entrance; use lots for lot markers.",
    )
    parser.add_argument(
        "--type",
        default="block",
        help="Map feature type: block, pathway, boundary, entrance. Only used with --mode map-feature.",
    )
    args = parser.parse_args()

    data = json.loads(Path(args.input).read_text(encoding="utf-8"))
    features = data.get("features", [])

    rows = (
        map_feature_rows(features, args.type)
        if args.mode == "map-feature"
        else lot_rows(features)
    )
    fields = MAP_FEATURE_FIELDS if args.mode == "map-feature" else LOT_FIELDS

    with Path(args.output).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {args.output}")


def map_feature_rows(features, default_type):
    rows = []
    for index, feature in enumerate(features, start=1):
        props = feature.get("properties") or {}
        geometry = feature.get("geometry")
        wkt = geometry_to_wkt(geometry)
        if not wkt:
            continue

        fid = text(props, "fid") or text(props, "id") or str(feature.get("id") or index)
        name = (
            text(props, "feature_name")
            or text(props, "name")
            or text(props, "block_number")
            or fid
        )

        rows.append(
            {
                "feature_type": text(props, "feature_type") or default_type,
                "feature_name": name,
                "name": name,
                "block_number": text(props, "block_number"),
                "fid": fid,
                "qgis_feature_id": text(props, "qgis_feature_id") or fid,
                "geometry_wkt": wkt,
                "wkt": "",
                "stroke_color": text(props, "stroke_color"),
                "fill_color": text(props, "fill_color"),
                "stroke_width": text(props, "stroke_width"),
                "sort_order": text(props, "sort_order") or sort_order_for(default_type),
                "is_visible": text(props, "is_visible") or "true",
            }
        )
    return rows


def lot_rows(features):
    rows = []
    for index, feature in enumerate(features, start=1):
        props = feature.get("properties") or {}
        geometry = feature.get("geometry")
        center = geometry_center(geometry)
        if center is None:
            continue

        lon, lat = center
        fid = text(props, "qgis_feature_id") or text(props, "fid") or str(feature.get("id") or index)
        block_number = text(props, "block_number")
        lot_number = text(props, "lot_number")
        lot_label = text(props, "lot_label")
        if not lot_label and block_number and lot_number:
            lot_label = f"{block_number}-{lot_number}"

        rows.append(
            {
                "qgis_feature_id": fid,
                "block_number": block_number,
                "lot_number": lot_number,
                "lot_label": lot_label,
                "lot_class_type": text(props, "lot_class_type") or text(props, "lot_class"),
                "price": text(props, "price") or "0",
                "status": text(props, "status") or "Available",
                "lon": f"{lon:.10f}",
                "lat": f"{lat:.10f}",
                "polygon_geo": json.dumps(geometry, separators=(",", ":")) if geometry else "",
            }
        )
    return rows


def text(props, key):
    value = props.get(key)
    if value is None:
        return ""
    return str(value).strip()


def sort_order_for(feature_type):
    return {
        "boundary": "10",
        "block": "20",
        "pathway": "30",
        "entrance": "40",
    }.get(feature_type, "100")


def geometry_to_wkt(geometry):
    if not geometry:
        return ""
    kind = geometry.get("type")
    coords = geometry.get("coordinates")
    if not kind or coords is None:
        return ""

    if kind == "Point":
        return f"POINT ({coord(coords)})"
    if kind == "MultiPoint":
        return f"MULTIPOINT ({', '.join(coord(point) for point in coords)})"
    if kind == "LineString":
        return f"LINESTRING ({coord_list(coords)})"
    if kind == "MultiLineString":
        return f"MULTILINESTRING ({', '.join(paren(coord_list(line)) for line in coords)})"
    if kind == "Polygon":
        return f"POLYGON ({', '.join(paren(coord_list(ring)) for ring in coords)})"
    if kind == "MultiPolygon":
        polygons = []
        for polygon in coords:
            rings = ", ".join(paren(coord_list(ring)) for ring in polygon)
            polygons.append(paren(rings))
        return f"MULTIPOLYGON ({', '.join(polygons)})"
    return ""


def geometry_center(geometry):
    if not geometry:
        return None
    kind = geometry.get("type")
    coords = geometry.get("coordinates")
    if kind == "Point":
        return float(coords[0]), float(coords[1])
    points = flatten_points(coords)
    if not points:
        return None
    lon = sum(point[0] for point in points) / len(points)
    lat = sum(point[1] for point in points) / len(points)
    return lon, lat


def flatten_points(value):
    if not isinstance(value, list):
        return []
    if len(value) >= 2 and all(isinstance(item, (int, float)) for item in value[:2]):
        return [(float(value[0]), float(value[1]))]
    points = []
    for item in value:
        points.extend(flatten_points(item))
    return points


def coord(value):
    return f"{float(value[0]):.10f} {float(value[1]):.10f}"


def coord_list(values):
    return ", ".join(coord(value) for value in values)


def paren(value):
    return f"({value})"


if __name__ == "__main__":
    main()
