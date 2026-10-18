# Low-end web comparison client

This is an isolated Preact + Leaflet prototype for comparing startup and map interaction on low-end devices. It uses the existing Supabase backend and the same `lot_markers`/`cemetery_lot` records. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`, then run `npm install && npm run dev` from this directory.

The client deliberately keeps the first version small: Canvas based Leaflet markers, a viewport buffer, no route or admin mutation UI, and no changes to Supabase schema or data. It is a comparison target, not a replacement for the Flutter application yet.
