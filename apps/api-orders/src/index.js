const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  database: process.env.DB_NAME || 'appdb',
});

const SERVICE_NAME = 'api-orders';
const PORT = process.env.PORT || 3002;

async function initDb() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS orders (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      status VARCHAR(20) DEFAULT 'pending',
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
}

app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE_NAME }));
app.get('/ready', async (req, res) => {
  try { await pool.query('SELECT 1'); res.json({ status: 'ready' }); }
  catch (e) { res.status(503).json({ status: 'not ready', error: e.message }); }
});

app.get('/orders', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM orders ORDER BY id DESC LIMIT 100');
    res.json(result.rows);
  } catch (e) {
    console.error(JSON.stringify({ level: 'error', service: SERVICE_NAME, msg: e.message }));
    res.status(500).json({ error: 'internal error' });
  }
});

app.post('/orders', async (req, res) => {
  const { user_id, product_id, quantity } = req.body;
  if (!user_id || !product_id) return res.status(400).json({ error: 'user_id and product_id required' });
  try {
    const result = await pool.query(
      'INSERT INTO orders (user_id, product_id, quantity) VALUES ($1, $2, $3) RETURNING *',
      [user_id, product_id, quantity || 1]
    );
    console.log(JSON.stringify({ level: 'info', service: SERVICE_NAME, msg: 'order created', user_id }));
    res.status(201).json(result.rows[0]);
  } catch (e) {
    console.error(JSON.stringify({ level: 'error', service: SERVICE_NAME, msg: e.message }));
    res.status(500).json({ error: 'internal error' });
  }
});

initDb().then(() => app.listen(PORT, () => console.log(`${SERVICE_NAME} listening on ${PORT}`)))
  .catch((e) => { console.error('DB init failed', e); process.exit(1); });
