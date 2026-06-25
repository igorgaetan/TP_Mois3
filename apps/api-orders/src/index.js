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

// =============================================================================
// === ROUTES AVEC LE PREFIXE /api/orders ===
// =============================================================================
const router = express.Router();

// L'ALB enverra : /api/orders/health
router.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE_NAME }));

// L'ALB enverra : /api/orders/ready
router.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (e) {
    res.status(503).json({ status: 'not ready', error: e.message });
  }
});

// L'ALB enverra : /api/orders
router.get('/', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM orders ORDER BY id DESC LIMIT 100');
    res.json(result.rows);
  } catch (e) {
    console.error(JSON.stringify({ level: 'error', service: SERVICE_NAME, msg: e.message }));
    res.status(500).json({ error: 'internal error' });
  }
});

// L'ALB enverra : /api/orders
router.post('/', async (req, res) => {
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

// ON APPLIQUE LE PREFIXE ICI : Toutes les routes du router commencent par /api/orders
app.use('/api/orders', router);



// =============================================================================

app.listen(PORT, () => console.log(`${SERVICE_NAME} listening on ${PORT}`));

initDb()
  .then(() => console.log(JSON.stringify({ level: 'info', service: SERVICE_NAME, msg: 'DB initialized' })))
  .catch((e) => console.error(JSON.stringify({ level: 'error', service: SERVICE_NAME, msg: 'DB init failed', error: e.message })));