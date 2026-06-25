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

const SERVICE_NAME = 'api-users';
const PORT = process.env.PORT || 3001;

async function initDb() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      email VARCHAR(100) UNIQUE NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
}

// === ROUTER POUR /api/users ===
const router = express.Router();

// Intercepte : /api/users/health
router.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE_NAME }));

// Intercepte : /api/users/ready
router.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (e) {
    res.status(503).json({ status: 'not ready', error: e.message });
  }
});

// Intercepte : /api/users
router.get('/', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM users ORDER BY id DESC LIMIT 100');
    res.json(result.rows);
  } catch (e) {
    console.error(JSON.stringify({ level: 'error', service: SERVICE_NAME, msg: e.message }));
    res.status(500).json({ error: 'internal error' });
  }
});

// Intercepte : /api/users
router.post('/', async (req, res) => {
  const { name, email } = req.body;
  if (!name || !email) return res.status(400).json({ error: 'name and email required' });
  try {
    const result = await pool.query(
      'INSERT INTO users (name, email) VALUES ($1, $2) RETURNING *',
      [name, email]
    );
    console.log(JSON.stringify({ level: 'info', service: SERVICE_NAME, msg: 'user created', email }));
    res.status(201).json(result.rows[0]);
  } catch (e) {
    console.error(JSON.stringify({ level: 'error', service: SERVICE_NAME, msg: e.message }));
    res.status(500).json({ error: 'internal error' });
  }
});

// Liaison du préfixe global
app.use('/api/users', router);

app.listen(PORT, () => console.log(`${SERVICE_NAME} listening on ${PORT}`));

initDb()
  .then(() => console.log(JSON.stringify({ level: 'info', service: SERVICE_NAME, msg: 'DB initialized' })))
  .catch((e) => console.error(JSON.stringify({ level: 'error', service: SERVICE_NAME, msg: 'DB init failed', error: e.message })));