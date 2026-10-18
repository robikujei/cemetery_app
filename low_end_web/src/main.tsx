import { render } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import L from 'leaflet';
import { createClient } from '@supabase/supabase-js';
import 'leaflet/dist/leaflet.css';
import './style.css';

const supabase = createClient(import.meta.env.VITE_SUPABASE_URL, import.meta.env.VITE_SUPABASE_ANON_KEY);
type Lot = { lot_id: number; lot_number?: string; status?: string; x_percent: number; y_percent: number };
const center: L.LatLngExpression = [7.318551542, 125.662934679];

function MapView({ lots, selected, onSelect }: { lots: Lot[]; selected: Lot | null; onSelect: (lot: Lot) => void }) {
  const host = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map>();
  const markers = useRef<L.LayerGroup>();
  useEffect(() => {
    if (!host.current) return;
    map.current = L.map(host.current, { center, zoom: 19, zoomControl: false, preferCanvas: true });
    L.control.zoom({ position: 'bottomright' }).addTo(map.current);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxNativeZoom: 19, maxZoom: 22 }).addTo(map.current);
    markers.current = L.layerGroup().addTo(map.current);
    return () => { map.current?.remove(); map.current = undefined; };
  }, []);
  useEffect(() => {
    if (!map.current || !markers.current) return;
    markers.current.clearLayers();
    const bounds = map.current.getBounds().pad(0.35);
    for (const lot of lots) {
      // Production can replace this point conversion with the configured map spans.
      const point: L.LatLngExpression = [center[0] + (50 - lot.y_percent) * 0.000036, center[1] + (lot.x_percent - 50) * 0.000046];
      if (!bounds.contains(point)) continue;
      const marker = L.circleMarker(point, { radius: selected?.lot_id === lot.lot_id ? 8 : 5, color: lot.status === 'Occupied' ? '#2f6f43' : '#7c8a7d', fillOpacity: 0.8 });
      marker.on('click', () => onSelect(lot));
      marker.bindTooltip(`Lot ${lot.lot_number ?? lot.lot_id}`, { direction: 'top' });
      marker.addTo(markers.current);
    }
  }, [lots, selected]);
  return <div ref={host} class="map" />;
}

export function App() {
  const [lots, setLots] = useState<Lot[]>([]);
  const [selected, setSelected] = useState<Lot | null>(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => { (async () => {
    const { data } = await supabase.from('lot_markers').select('x_percent,y_percent,cemetery_lot(lot_id,lot_number,status)').limit(2000);
    setLots((data ?? []).map((row: any) => ({ x_percent: row.x_percent, y_percent: row.y_percent, ...row.cemetery_lot })));
    setLoading(false);
  })(); }, []);
  return <main><header><strong>Eternal Garden</strong><span>{loading ? 'Loading lots…' : `${lots.length} lots`}</span></header><MapView lots={lots} selected={selected} onSelect={setSelected} />{selected && <aside><b>Lot {selected.lot_number ?? selected.lot_id}</b><span>{selected.status ?? 'Unknown'}</span><button onClick={() => setSelected(null)}>Close</button></aside>}</main>;
}
render(<App />, document.getElementById('app')!);
