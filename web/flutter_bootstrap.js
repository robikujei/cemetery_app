{{flutter_js}}
{{flutter_build_config}}

// Flutter no longer ships a service worker for this build. Remove any
// registration left by an older deployment before loading the application;
// otherwise it can serve stale JavaScript and leave role-specific routes blank.
finalizeServiceWorkers().then(() => {
  _flutter.loader.load();
});

async function finalizeServiceWorkers() {
  if (!('serviceWorker' in navigator)) return;
  const registrations = await navigator.serviceWorker.getRegistrations();
  await Promise.all(registrations.map((registration) => registration.unregister()));
}
