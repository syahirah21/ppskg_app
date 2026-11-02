{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: Flutter's own service worker is deprecated and
// only removes itself, which would also remove the site's offline cache
// (offline_sw.js, registered in index.html).
_flutter.loader.load();
