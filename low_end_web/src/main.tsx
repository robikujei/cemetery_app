import { render } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import L from 'leaflet';
import { createClient } from '@supabase/supabase-js';
import 'leaflet/dist/leaflet.css';
import './style.css';

const supabase = createClient(import.meta.env.VITE_SUPABASE_URL, import.meta.env.VITE_SUPABASE_ANON_KEY);
type Lot = { lot_id: number; lot_number?: string; status?: string; x_percent: number; y_percent: number; polygon_geo?: unknown };
const center: L.LatLngExpression = [7.318551542, 125.662934679];

function MapView({ lots, selected, onSelect }: { lots: Lot[]; selected: Lot | null; onSelect: (lot: Lot) => void }) {
  const host = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map>();
  const markers = useRef<L.LayerGroup>();
  const polygons = useRef<L.LayerGroup>();
  useEffect(() => {
    if (!host.current) return;
    map.current = L.map(host.current, { center, zoom: 17, zoomControl: false, preferCanvas: true });
    L.control.zoom({ position: 'bottomright' }).addTo(map.current);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxNativeZoom: 19, maxZoom: 22 }).addTo(map.current);
    markers.current = L.layerGroup().addTo(map.current);
    polygons.current = L.layerGroup().addTo(map.current);
    return () => { map.current?.remove(); map.current = undefined; };
  }, []);
  useEffect(() => {
    if (!map.current || !markers.current || !polygons.current) return;
    markers.current.clearLayers();
    polygons.current.clearLayers();
    const allPoints: L.LatLngExpression[] = [];
    for (const lot of lots) {
      // Production can replace this point conversion with the configured map spans.
      const point: L.LatLngExpression = [center[0] + (50 - lot.y_percent) * 0.000036, center[1] + (lot.x_percent - 50) * 0.000046];
      const rings = geoRings(lot.polygon_geo);
      for (const ring of rings) {
        allPoints.push(...ring);
        const polygon = L.polygon(ring, { color: selected?.lot_id === lot.lot_id ? '#174a27' : '#4d7658', weight: 1, fillColor: lot.status === 'Occupied' ? '#6e9f78' : '#b8d1bd', fillOpacity: selected?.lot_id === lot.lot_id ? 0.75 : 0.45 });
        polygon.on('click', () => onSelect(lot));
        polygon.bindTooltip(`Lot ${lot.lot_number ?? lot.lot_id}`, { direction: 'top' });
        polygon.addTo(polygons.current);
      }
      const marker = L.circleMarker(point, { radius: selected?.lot_id === lot.lot_id ? 8 : 5, color: lot.status === 'Occupied' ? '#2f6f43' : '#7c8a7d', fillOpacity: 0.8 });
      marker.on('click', () => onSelect(lot));
      marker.bindTooltip(`Lot ${lot.lot_number ?? lot.lot_id}`, { direction: 'top' });
      marker.addTo(markers.current);
    }
    if (allPoints.length > 2) map.current.fitBounds(L.latLngBounds(allPoints), { padding: [24, 24], maxZoom: 19, animate: false });
  }, [lots, selected]);
  return <div ref={host} class="map" />;
}

function geoRings(value: unknown): L.LatLngExpression[][] {
  if (!value) return [];
  const geo = typeof value === 'string' ? (() => { try { return JSON.parse(value); } catch { return null; } })() : value as any;
  const geometry = geo?.type === 'Feature' ? geo.geometry : geo;
  if (!geometry?.coordinates) return [];
  const convert = (ring: any[]) => ring.map(([lng, lat]) => [Number(lat), Number(lng)] as L.LatLngExpression);
  if (geometry.type === 'Polygon') return geometry.coordinates.map(convert);
  if (geometry.type === 'MultiPolygon') return geometry.coordinates.flatMap((polygon: any[]) => polygon.map(convert));
  return [];
}

export function App() {
  const [lots, setLots] = useState<Lot[]>([]);
  const [selected, setSelected] = useState<Lot | null>(null);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [user, setUser] = useState<any>(null);
  const [authError, setAuthError] = useState('');
  useEffect(() => { supabase.auth.getUser().then(({ data }) => setUser(data.user)); const { data } = supabase.auth.onAuthStateChange((_event, session) => setUser(session?.user ?? null)); return () => data.subscription.unsubscribe(); }, []);
  useEffect(() => { (async () => {
    const { data } = await supabase.from('lot_markers').select('x_percent,y_percent,cemetery_lot(lot_id,lot_number,status,polygon_geo)').limit(2000);
    setLots((data ?? []).map((row: any) => ({ x_percent: row.x_percent, y_percent: row.y_percent, ...row.cemetery_lot })));
    setLoading(false);
  })(); }, []);
  const visibleLots = lots.filter((lot) => !query || String(lot.lot_number ?? lot.lot_id).toLowerCase().includes(query.toLowerCase()));
  async function signIn(e: Event) { e.preventDefault(); setAuthError(''); const { data, error } = await supabase.auth.signInWithPassword({ email, password }); if (error) setAuthError(error.message); else setUser(data.user); }
  return <main><header><strong>Eternal Garden</strong><span>{loading ? 'Loading lots…' : `${visibleLots.length} lots`}</span><nav>{user ? <><span>{user.email}</span><button onClick={() => supabase.auth.signOut()}>Sign out</button></> : <span>Visitor</span>}</nav></header><section class="toolbar"><input aria-label="Search lots" value={query} onInput={(e) => setQuery((e.currentTarget as HTMLInputElement).value)} placeholder="Search lot number" />{!user && <details><summary>Sign in</summary><form onSubmit={signIn}><input type="email" required value={email} onInput={(e) => setEmail((e.currentTarget as HTMLInputElement).value)} placeholder="Email" /><input type="password" required value={password} onInput={(e) => setPassword((e.currentTarget as HTMLInputElement).value)} placeholder="Password" /><button>Sign in</button>{authError && <small>{authError}</small>}</form></details>}</section><MapView lots={visibleLots} selected={selected} onSelect={setSelected} />{selected && <aside><b>Lot {selected.lot_number ?? selected.lot_id}</b><span>{selected.status ?? 'Unknown'}</span><button onClick={() => setSelected(null)}>Close</button></aside>}</main>;
}
render(<App />, document.getElementById('app')!);
