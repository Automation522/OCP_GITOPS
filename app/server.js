const express = require('express');
const { Pool } = require('pg');
const dotenv = require('dotenv');

const DEFAULT_LIMIT = 10;
const MAX_LIMIT = 50;

// Charge les variables locales si un fichier .env est présent (usage hors prod)
dotenv.config({ path: '.env', override: false });

function buildDbConfigFromEnv(env = process.env) {
  return {
    host: env.DB_HOST || 'postgres',
    port: parseInt(env.DB_PORT || '5432', 10),
    user: env.DB_USER || 'customer',
    password: env.DB_PASSWORD || 'customer',
    database: env.DB_NAME || 'customers',
    ssl: env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false
  };
}

async function fetchLatestCustomers(db, limit = DEFAULT_LIMIT) {
  const effectiveLimit = Math.min(Math.max(limit, 1), MAX_LIMIT);
  const query = `
    SELECT id, first_name, last_name, email, last_purchase_at
    FROM customer
    ORDER BY last_purchase_at DESC NULLS LAST, id DESC
    LIMIT $1
  `;
  const result = await db.query(query, [effectiveLimit]);
  return result.rows;
}

function renderHtml(customers) {
  const rows = customers
    .map(
      (customer) => `
        <tr>
          <td>${customer.id}</td>
          <td>${customer.first_name} ${customer.last_name}</td>
          <td>${customer.email || ''}</td>
          <td>${customer.last_purchase_at ? new Date(customer.last_purchase_at).toISOString() : 'n/a'}</td>
        </tr>
      `
    )
    .join('');

  return `<!DOCTYPE html>
  <html lang="fr">
    <head>
      <meta charset="utf-8" />
      <title>Clients récents</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 0 auto; padding: 2rem; max-width: 960px; background: #f9fafb; }
        h1 { text-align: center; }
        table { width: 100%; border-collapse: collapse; margin-top: 1.5rem; }
        th, td { border: 1px solid #d1d5db; padding: 0.5rem; text-align: left; }
        th { background: #111827; color: #fff; }
        tbody tr:nth-child(even) { background: #f3f4f6; }
      </style>
    </head>
    <body>
      <h1>Derniers clients</h1>
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Nom</th>
            <th>Email</th>
            <th>Dernier achat</th>
          </tr>
        </thead>
        <tbody>
          ${rows || '<tr><td colspan="4">Aucune donnée disponible</td></tr>'}
        </tbody>
      </table>
    </body>
  </html>`;
}

function createApp({ db }) {
  if (!db || typeof db.query !== 'function') {
    throw new Error('Une instance PostgreSQL valide (avec méthode query) est requise');
  }

  const app = express();

  app.get('/healthz', (req, res) => {
    res.status(200).json({ status: 'ok' });
  });

  app.get('/', async (req, res) => {
    const limit = parseInt(req.query.limit || `${DEFAULT_LIMIT}`, 10) || DEFAULT_LIMIT;
    try {
      const customers = await fetchLatestCustomers(db, limit);
      res.set('Content-Type', 'text/html; charset=utf-8');
      res.status(200).send(renderHtml(customers));
    } catch (error) {
      console.error('Erreur lors de la récupération des clients', error);
      res.status(500).send('Erreur interne, voir les logs applicatifs');
    }
  });

  return app;
}

function startServer() {
  const port = parseInt(process.env.PORT || '8080', 10);
  const pool = new Pool(buildDbConfigFromEnv());
  const app = createApp({ db: pool });

  app.listen(port, () => {
    console.log(`Serveur démarré sur le port ${port}`);
  });
}

if (require.main === module) {
  startServer();
}

module.exports = {
  createApp,
  buildDbConfigFromEnv,
  fetchLatestCustomers,
  renderHtml,
  DEFAULT_LIMIT,
  MAX_LIMIT
};
