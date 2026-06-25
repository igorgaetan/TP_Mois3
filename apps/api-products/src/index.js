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
  ssl: {
    rejectUnauthorized: false   // accepte le certificat auto-signé d'AWS RDS
  }
});

const SERVICE_NAME = 'api-products';
const PORT = process.env.PORT || 3003;

async function initDb() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS products (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      price NUMERIC(10,2) NOT NULL,
      stock INTEGER DEFAULT 0,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
}

// === ROUTER POUR /api/products ===
const router = express.Router();

// Intercepte : /api/products/health
router.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE_NAME }));

// Intercepte : /api/products/ready
router.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (e) {
    res.status(503).json({ status: 'not ready', error: e.message });
  }
});

// Intercepte : /api/products
router.get('/', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM products ORDER BY id DESC LIMIT 100');
    res.json(result.rows);
  } catch (e) {
    console.error(JSON.stringify({ level: 'error', service: SERVICE_NAME, msg: e.message }));
    res.status(500).json({ error: 'internal error' });
  }
});

// Intercepte : /api/products
router.post('/', async (req, res) => {
  const { name, price, stock } = req.body;
  if (!name || price === undefined) return res.status(400).json({ error: 'name and price required' });
  try {
    const result = await pool.query(
      'INSERT INTO products (name, price, stock) VALUES ($1, $2, $3) RETURNING *',
      [name, price, stock || 0]
    );
    console.log(JSON.stringify({ level: 'info', service: SERVICE_NAME, msg: 'product created', name }));
    res.status(201).json(result.rows[0]);
  } catch (e) {
    console.error(JSON.stringify({ level: 'error', service: SERVICE_NAME, msg: e.message }));
    res.status(500).json({ error: 'internal error' });
  }
});

// Liaison du préfixe global
app.use('/api/products', router);

app.listen(PORT, () => console.log(`${SERVICE_NAME} listening on ${PORT}`));

initDb()
  .then(() => console.log(JSON.stringify({ level: 'info', service: SERVICE_NAME, msg: 'DB initialized' })))
  .catch((e) => console.error(JSON.stringify({ level: 'error', service: SERVICE_NAME, msg: 'DB init failed', error: e.message })));