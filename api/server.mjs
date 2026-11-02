// API de démonstration, sans paiement ni persistance.
// Le serveur recalcule les prix : il ne fait jamais confiance au total du client.
import { randomUUID } from 'node:crypto';

const products = [
  { id: 'notebook', name: 'Carnet de terrain', price: 1800 },
  { id: 'cup', name: 'Tasse atelier', price: 2400 },
  { id: 'bag', name: 'Sac quotidien', price: 4200 },
];

export function demoApi(req, res, next) {
  const url = new URL(req.url, 'http://localhost');
  if (!url.pathname.startsWith('/api/')) return next();
  const send = (status, data) => {
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(data));
  };
  const scenario = url.searchParams.get('scenario');
  if (req.method === 'GET' && url.pathname === '/api/products') {
    setTimeout(() => {
      if (scenario === 'unavailable') return send(503, { error: 'Indisponibilité simulée' });
      if (scenario === 'invalid-json') return send(200, [{ id: 'broken', name: 'Produit invalide', price: 'pas un entier' }]);
      send(200, products);
    }, 350);
    return;
  }
  if (req.method === 'POST' && url.pathname === '/api/orders') {
    let body = '';
    let oversized = false;
    req.on('data', chunk => {
      if (oversized) return;
      body += chunk;
      if (body.length > 16384) {
        oversized = true;
        send(413, { error: 'Requête trop volumineuse' });
      }
    });
    req.on('end', () => {
      if (oversized) return;
      setTimeout(() => {
        if (scenario === 'unavailable') return send(503, { error: 'Indisponibilité simulée' });
        try {
          const { email, items } = JSON.parse(body);
          if (typeof email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !Array.isArray(items) || !items.length || items.length > products.length) {
            return send(400, { error: 'Commande invalide' });
          }
          const ids = new Set();
          let subtotal = 0;
          for (const item of items) {
            const product = products.find(p => p.id === item?.id);
            if (!product || ids.has(item.id) || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 99) {
              return send(400, { error: 'Article ou quantité invalide' });
            }
            ids.add(item.id);
            subtotal += product.price * item.quantity;
          }
          const total = subtotal - (subtotal >= 10000 ? Math.floor(subtotal / 10) : 0) + (subtotal >= 10000 ? 0 : 490);
          send(201, { id: `ELM-${randomUUID().slice(0, 8).toUpperCase()}`, total });
        } catch {
          send(400, { error: 'JSON invalide' });
        }
      }, 350);
    });
    return;
  }
  send(404, { error: 'Route inconnue' });
}
