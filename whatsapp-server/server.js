import express from 'express';
import fetch from 'node-fetch';
import cors from 'cors';
import dotenv from 'dotenv';

dotenv.config();
const app = express();
app.use(cors());
app.use(express.json());

const WHATSAPP_PHONE_ID = process.env.WHATSAPP_PHONE_ID || '';
const WHATSAPP_TOKEN = process.env.WHATSAPP_TOKEN || '';
import fs from 'fs';
import path from 'path';

const GROUPS_FILE = path.resolve(process.cwd(), 'groups.json');

function loadGroups() {
  try {
    if (!fs.existsSync(GROUPS_FILE)) return {};
    const txt = fs.readFileSync(GROUPS_FILE, 'utf8');
    return JSON.parse(txt || '{}');
  } catch (e) {
    console.error('Failed to load groups', e);
    return {};
  }
}

function saveGroups(obj) {
  try {
    fs.writeFileSync(GROUPS_FILE, JSON.stringify(obj, null, 2));
  } catch (e) {
    console.error('Failed to save groups', e);
  }
}

// Basic API key middleware (for dev). In prod, use JWT or OAuth.
const API_KEY = process.env.API_KEY || '';
function requireApiKey(req, res, next) {
  const auth = req.header('authorization') ?? req.header('Authorization');
  if (!auth) return res.status(401).json({ error: 'missing authorization' });
  if (API_KEY && auth !== `Bearer ${API_KEY}`) return res.status(403).json({ error: 'invalid api key' });
  next();
}

app.post('/api/send-help', requireApiKey, async (req, res) => {
  const { toPhone, fullMessage } = req.body;
  if (!fullMessage) return res.status(400).json({ error: 'missing fullMessage' });

  const to = toPhone || req.body.toPhone || '';
  if (!to) return res.status(400).json({ error: 'missing toPhone (recipient) in request or server config)' });

  try {
    const url = `https://graph.facebook.com/v17.0/${WHATSAPP_PHONE_ID}/messages`;
    const payload = {
      messaging_product: 'whatsapp',
      to: to,
      text: { body: fullMessage }
    };
    const r = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${WHATSAPP_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    const data = await r.json();
    if (!r.ok) return res.status(500).json({ ok: false, data });
    return res.json({ ok: true, data });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: err.message });
  }
});

// Group management endpoints (simple JSON-backed storage)
app.post('/api/group', requireApiKey, (req, res) => {
  const { name } = req.body || {};
  const groups = loadGroups();
  const id = Math.random().toString(36).slice(2, 9);
  groups[id] = { id, name: name || 'Unnamed Group', members: [] };
  saveGroups(groups);
  return res.json(groups[id]);
});

app.get('/api/group/:id', requireApiKey, (req, res) => {
  const groups = loadGroups();
  const g = groups[req.params.id];
  if (!g) return res.status(404).json({ error: 'not found' });
  return res.json(g);
});

app.post('/api/group/:id/add', requireApiKey, (req, res) => {
  const { phone } = req.body || {};
  if (!phone) return res.status(400).json({ error: 'missing phone' });
  const groups = loadGroups();
  const g = groups[req.params.id];
  if (!g) return res.status(404).json({ error: 'group not found' });
  if (!g.members.includes(phone)) g.members.push(phone);
  saveGroups(groups);
  return res.json(g);
});

app.post('/api/group/:id/remove', requireApiKey, (req, res) => {
  const { phone } = req.body || {};
  if (!phone) return res.status(400).json({ error: 'missing phone' });
  const groups = loadGroups();
  const g = groups[req.params.id];
  if (!g) return res.status(404).json({ error: 'group not found' });
  g.members = g.members.filter((p) => p !== phone);
  saveGroups(groups);
  return res.json(g);
});

app.get('/', (req, res) => res.send('WhatsApp demo server running'));

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Server listening on :${port}`));
