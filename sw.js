// NQ: служебный файл для уведомлений о намазе.
// Ничего не кэширует, поэтому обновления сайта приходят сразу.
self.addEventListener('install', () => self.skipWaiting())
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()))
self.addEventListener('notificationclick', (e) => {
  e.notification.close()
  e.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    for (const c of all) { if ('focus' in c) return c.focus() }
    if (self.clients.openWindow) return self.clients.openWindow('./#today')
  })())
})
