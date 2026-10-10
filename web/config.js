// Public client config. The publishable key is meant to be public; access is enforced by
// Google sign-in plus RLS on realtime.messages (supabase/migrations).
window.DOUBLE_CONFIG = {
  supabaseUrl: 'https://YOUR-PROJECT.supabase.co',
  supabaseKey: 'YOUR-PUBLISHABLE-KEY',
  room: 'double-office',
  domain: 'glanser.com'
};
