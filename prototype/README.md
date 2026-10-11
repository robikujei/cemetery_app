# Evergreen clickable prototype

Open `index.html` directly in a modern browser. No install, backend, Flutter SDK, or account is needed. All assets are local.

This is a standalone design prototype for the Flutter cemetery app, using an illustrative Evergreen identity. It does not change the production Flutter screens or connect to Supabase.

## Walkthrough

1. Search for **Maria**, select her memorial, and save or unsave it.
2. Choose **Find on map**, select a block, and preview a walking route.
3. Create a visit pass and choose **Try gate officer check-in**.
4. Validate the populated code; the completed visit appears in the visitor log. Checking in the same pass again is rejected.
5. Switch roles using **Explore as** to view the admin dashboard, burial records, lot management, and lot owner preview.
6. Toggle dark/light mode in the sidebar or edit the visitor demo profile.

Search, filters, memorial selection, saved memorials, pass creation, validation, visit history, and profile edits work locally. Theme preference persists when browser storage is available; all other state resets on reload. A new pass replaces the previous active pass.

Records and ownership are fictional. The map and route are illustrative, not geographic navigation. The pass is explicitly non-scannable; live QR generation, camera scanning, authentication, record editing, payments, and backend persistence are outside this prototype.

To serve locally instead of opening the file, run `python -m http.server 4173 --bind 127.0.0.1` from this directory and open http://127.0.0.1:4173.
