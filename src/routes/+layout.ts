// Everything runs on the device: the database is SQLite in the app, so there is
// no server to render on and nothing to prerender against.
export const ssr = false;
export const prerender = false;
export const trailingSlash = 'never';
