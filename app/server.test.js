const test = require('node:test');
const assert = require('node:assert/strict');
const supertest = require('supertest');
const {
  createApp,
  buildDbConfigFromEnv,
  fetchLatestCustomers,
  DEFAULT_LIMIT,
  MAX_LIMIT
} = require('./server');

test('buildDbConfigFromEnv applique les valeurs par défaut', () => {
  const config = buildDbConfigFromEnv({});
  assert.equal(config.host, 'postgres');
  assert.equal(config.port, 5432);
  assert.equal(config.user, 'customer');
  assert.equal(config.database, 'customers');
});

test('fetchLatestCustomers limite la valeur maximum', async () => {
  const executed = [];
  const fakeDb = {
    query: async (_sql, params) => {
      executed.push(params[0]);
      return { rows: [] };
    }
  };

  await fetchLatestCustomers(fakeDb, MAX_LIMIT + 10);
  assert.equal(executed[0], MAX_LIMIT);
});

test('GET / renvoie le HTML contenant les clients', async () => {
  const fakeDb = {
    query: async () => ({
      rows: [
        { id: 1, first_name: 'Alice', last_name: 'Martin', email: 'alice@example.com', last_purchase_at: new Date() }
      ]
    })
  };

  const app = createApp({ db: fakeDb });
  const response = await supertest(app).get('/');

  assert.equal(response.statusCode, 200);
  assert.match(response.text, /Derniers clients/);
  assert.match(response.text, /Alice Martin/);
});

test('GET /healthz renvoie ok', async () => {
  const fakeDb = { query: async () => ({ rows: [] }) };
  const app = createApp({ db: fakeDb });
  const response = await supertest(app).get('/healthz');

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.body, { status: 'ok' });
});
