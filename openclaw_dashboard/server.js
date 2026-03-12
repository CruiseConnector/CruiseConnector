'use strict';

require('dotenv').config();
const express = require('express');
const session = require('express-session');
const fs = require('fs');

const app = express();
const HOST = '0.0.0.0';
const PORT = 3000;

const CREDENTIALS = {
  username: process.env.ADMIN_USERNAME || 'vucko',
  password: process.env.ADMIN_PASSWORD || 'fallback'
};

const TASKS_PATH = '/home/vucko1/.openclaw/workspace/openclaw_dashboard/tasks.md';

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(session({
  secret: process.env.SESSION_SECRET || 'fallback-secret',
  resave: false,
  saveUninitialized: false,
  cookie: { secure: false, maxAge: 24 * 60 * 60 * 1000 }
}));

function requireAuth(req, res, next) {
  if (req.session && req.session.authenticated) return next();
  if (req.path.startsWith('/api/')) return res.status(401).json({ error: 'Nicht eingeloggt' });
  res.redirect('/login');
}

function readTasks() {
  try { return JSON.parse(fs.readFileSync(TASKS_PATH, 'utf8')); }
  catch { return { backlog: [], inProgress: [], completed: [], stats: { total: 0, completed: 0 } }; }
}

function writeTasks(data) {
  data.stats = {
    total: data.backlog.length + data.inProgress.length + data.completed.length,
    completed: data.completed.length
  };
  fs.writeFileSync(TASKS_PATH, JSON.stringify(data, null, 2), 'utf8');
}

const loginPage = (err) => `<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>VuckoClaw</title>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;700&family=Syne:wght@700;800&display=swap" rel="stylesheet">
<style>
*{margin:0;padding:0;box-sizing:border-box}
:root{--bg:#080810;--surface:#0e0e1a;--border:#1e1e2e;--accent:#f0c040;--text:#c8c8d8;--muted:#444455}
body{background:var(--bg);color:var(--text);font-family:'JetBrains Mono',monospace;min-height:100vh;display:flex;align-items:center;justify-content:center;overflow:hidden}
.bg-grid{position:fixed;inset:0;background-image:linear-gradient(var(--border) 1px,transparent 1px),linear-gradient(90deg,var(--border) 1px,transparent 1px);background-size:40px 40px;opacity:.25;pointer-events:none}
.box{position:relative;width:400px;padding:48px 40px;background:var(--surface);border:1px solid var(--border);z-index:1}
.box::before{content:'';position:absolute;top:-1px;left:20px;right:20px;height:2px;background:var(--accent)}
.logo{font-family:'Syne',sans-serif;font-size:28px;font-weight:800;color:var(--accent);letter-spacing:2px;margin-bottom:4px}
.tagline{font-size:10px;color:var(--muted);letter-spacing:3px;margin-bottom:40px}
.field{margin-bottom:20px}
label{display:block;font-size:10px;color:var(--muted);letter-spacing:2px;margin-bottom:8px}
input{width:100%;background:#080810;border:1px solid var(--border);color:var(--text);padding:12px 14px;font-family:'JetBrains Mono',monospace;font-size:13px;outline:none;transition:border-color .2s}
input:focus{border-color:var(--accent)}
.btn-login{width:100%;background:var(--accent);color:#080810;border:none;padding:14px;font-family:'Syne',sans-serif;font-size:13px;font-weight:700;letter-spacing:3px;cursor:pointer;margin-top:8px;transition:opacity .2s}
.btn-login:hover{opacity:.85}
.err{background:#1a0810;border:1px solid #3a1020;color:#ff6b6b;padding:10px 14px;font-size:11px;margin-bottom:20px}
.corner{position:absolute;width:10px;height:10px;border-color:var(--accent);border-style:solid}
.tl{top:8px;left:8px;border-width:1px 0 0 1px}.tr{top:8px;right:8px;border-width:1px 1px 0 0}
.bl{bottom:8px;left:8px;border-width:0 0 1px 1px}.br{bottom:8px;right:8px;border-width:0 1px 1px 0}
</style>
</head>
<body>
<div class="bg-grid"></div>
<div class="box">
  <div class="corner tl"></div><div class="corner tr"></div><div class="corner bl"></div><div class="corner br"></div>
  <div class="logo">VUCKOCLAW</div>
  <div class="tagline">AUTONOMOUS FULLSTACK AGENT // vucko1</div>
  ${err ? '<div class="err">⚠ ' + err + '</div>' : ''}
  <form method="POST" action="/login">
    <div class="field"><label>USERNAME</label><input type="text" name="username" autofocus autocomplete="username"></div>
    <div class="field"><label>PASSWORD</label><input type="password" name="password" autocomplete="current-password"></div>
    <button class="btn-login" type="submit">AUTHENTICATE →</button>
  </form>
</div>
</body></html>`;

app.get('/login', (req, res) => res.send(loginPage(null)));
app.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (username === CREDENTIALS.username && password === CREDENTIALS.password) {
    req.session.authenticated = true;
    res.redirect('/');
  } else {
    res.send(loginPage('Ungültige Zugangsdaten.'));
  }
});
app.get('/logout', (req, res) => { req.session.destroy(); res.redirect('/login'); });

app.get('/api/tasks', requireAuth, (req, res) => res.json(readTasks()));

app.post('/api/tasks', requireAuth, (req, res) => {
  const { title, description } = req.body;
  if (!title?.trim()) return res.status(400).json({ error: 'Titel fehlt' });
  const tasks = readTasks();
  const task = { id: Date.now().toString(), title: title.trim(), description: (description||'').trim(), createdAt: new Date().toISOString(), completedAt: null };
  tasks.backlog.push(task);
  writeTasks(tasks);
  res.json({ success: true, task });
});

app.put('/api/tasks/:id', requireAuth, (req, res) => {
  const tasks = readTasks();
  for (const list of ['backlog','inProgress','completed']) {
    const t = tasks[list].find(t => t.id === req.params.id);
    if (t) {
      if (req.body.title !== undefined) t.title = req.body.title.trim();
      if (req.body.description !== undefined) t.description = req.body.description.trim();
      writeTasks(tasks);
      return res.json({ success: true, task: t });
    }
  }
  res.status(404).json({ error: 'Nicht gefunden' });
});

app.patch('/api/tasks/:id/move', requireAuth, (req, res) => {
  const { to } = req.body;
  if (!['backlog','inProgress','completed'].includes(to)) return res.status(400).json({ error: 'Ungültig' });
  const tasks = readTasks();
  let task = null;
  for (const list of ['backlog','inProgress','completed']) {
    const idx = tasks[list].findIndex(t => t.id === req.params.id);
    if (idx !== -1) { task = tasks[list].splice(idx,1)[0]; break; }
  }
  if (!task) return res.status(404).json({ error: 'Nicht gefunden' });
  if (to === 'completed') task.completedAt = new Date().toISOString();
  else task.completedAt = null;
  tasks[to].push(task);
  writeTasks(tasks);
  res.json({ success: true, task });
});

app.delete('/api/tasks/:id', requireAuth, (req, res) => {
  const tasks = readTasks();
  let found = false;
  for (const list of ['backlog','inProgress','completed']) {
    const idx = tasks[list].findIndex(t => t.id === req.params.id);
    if (idx !== -1) { tasks[list].splice(idx,1); found = true; break; }
  }
  if (!found) return res.status(404).json({ error: 'Nicht gefunden' });
  writeTasks(tasks);
  res.json({ success: true });
});

let agentStatus = { state: 'available', message: 'Bereit', lastUpdated: new Date().toISOString() };
app.get('/api/status', requireAuth, (req, res) => res.json({ ...agentStatus, uptime: process.uptime() }));
app.post('/api/status', requireAuth, (req, res) => {
  const { state, message } = req.body;
  if (!['available','busy','offline'].includes(state)) return res.status(400).json({ error: 'Ungültig' });
  agentStatus = { state, message: message||agentStatus.message, lastUpdated: new Date().toISOString() };
  res.json({ success: true });
});

const dashboard = `<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>VuckoClaw</title>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;600;700&family=Syne:wght@600;700;800&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#080810;--surface:#0e0e1a;--surface2:#12121f;--border:#1e1e2e;--border2:#252535;
  --accent:#f0c040;--green:#4ade80;--orange:#fb923c;--red:#f87171;
  --text:#c8c8d8;--muted:#555568;--muted2:#333345;
}
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--text);font-family:'JetBrains Mono',monospace;height:100vh;display:flex;overflow:hidden}
.sidebar{width:220px;min-width:220px;background:var(--surface);border-right:1px solid var(--border);display:flex;flex-direction:column;height:100vh}
.sidebar-logo{padding:24px 20px 20px;border-bottom:1px solid var(--border)}
.logo-text{font-family:'Syne',sans-serif;font-size:18px;font-weight:800;color:var(--accent);letter-spacing:2px}
.logo-sub{font-size:9px;color:var(--muted);letter-spacing:2px;margin-top:3px}
.nav{flex:1;padding:16px 0}
.nav-section{padding:6px 20px 4px;font-size:9px;color:var(--muted2);letter-spacing:2px}
.nav-item{display:flex;align-items:center;gap:10px;padding:10px 20px;cursor:pointer;font-size:11px;color:var(--muted);letter-spacing:1px;transition:all .15s;border-left:2px solid transparent}
.nav-item:hover{color:var(--text);background:var(--surface2)}
.nav-item.active{color:var(--accent);border-left-color:var(--accent);background:var(--surface2)}
.nav-badge{margin-left:auto;background:var(--accent);color:#080810;font-size:9px;font-weight:700;padding:1px 6px}
.sidebar-bottom{padding:16px 20px;border-top:1px solid var(--border)}
.agent-dot{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:6px}
.dot-available{background:var(--green);box-shadow:0 0 6px var(--green)}
.dot-busy{background:var(--orange);box-shadow:0 0 6px var(--orange)}
.dot-offline{background:var(--red)}
.agent-label{font-size:10px;color:var(--muted)}
.logout-btn{display:block;width:100%;background:none;border:1px solid var(--border2);color:var(--muted);padding:8px;font-family:'JetBrains Mono',monospace;font-size:10px;letter-spacing:1px;cursor:pointer;margin-top:10px;transition:all .15s}
.logout-btn:hover{border-color:var(--accent);color:var(--accent)}
.main{flex:1;display:flex;flex-direction:column;overflow:hidden}
.topbar{padding:16px 28px;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;background:var(--surface)}
.page-title{font-family:'Syne',sans-serif;font-size:16px;font-weight:700}
.topbar-right{display:flex;align-items:center;gap:16px;font-size:10px;color:var(--muted)}
.content{flex:1;overflow:auto;padding:24px 28px}
.page{display:none}.page.active{display:block}
.stats-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-bottom:24px}
.stat-card{background:var(--surface);border:1px solid var(--border);padding:20px 24px;position:relative;overflow:hidden}
.stat-card::after{content:'';position:absolute;bottom:0;left:0;right:0;height:2px}
.stat-card.s-open::after{background:var(--orange)}.stat-card.s-done::after{background:var(--green)}.stat-card.s-agent::after{background:var(--accent)}
.stat-label{font-size:9px;color:var(--muted);letter-spacing:2px;margin-bottom:10px}
.stat-value{font-family:'Syne',sans-serif;font-size:36px;font-weight:800;color:var(--accent);line-height:1}
.stat-sub{font-size:10px;color:var(--muted);margin-top:6px}
.ctrl-btn{background:var(--surface2);border:1px solid var(--border2);color:var(--muted);padding:6px 12px;font-family:'JetBrains Mono',monospace;font-size:10px;letter-spacing:1px;cursor:pointer;transition:all .15s;margin-right:6px;margin-top:12px}
.ctrl-btn:hover{border-color:var(--accent);color:var(--accent)}
.quick-card{background:var(--surface);border:1px solid var(--border);padding:20px 24px}
.add-row{display:flex;gap:10px}
.add-input{background:var(--surface2);border:1px solid var(--border);color:var(--text);padding:10px 14px;font-family:'JetBrains Mono',monospace;font-size:12px;outline:none;flex:1;transition:border-color .2s}
.add-input:focus{border-color:var(--accent)}
.add-input::placeholder{color:var(--muted2)}
.add-btn{background:var(--accent);color:#080810;border:none;padding:10px 18px;font-family:'Syne',sans-serif;font-size:11px;font-weight:700;letter-spacing:2px;cursor:pointer;transition:opacity .2s;white-space:nowrap}
.add-btn:hover{opacity:.85}
.board-toolbar{display:flex;gap:10px;margin-bottom:20px}
.board-cols{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;height:calc(100vh - 240px)}
.col{background:var(--surface);border:1px solid var(--border);display:flex;flex-direction:column}
.col-head{padding:14px 16px;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between}
.col-name{font-size:10px;letter-spacing:2px;font-weight:600}
.col-backlog .col-name{color:var(--muted)}.col-inprogress .col-name{color:var(--orange)}.col-completed .col-name{color:var(--green)}
.col-count{font-size:10px;color:var(--muted2);background:var(--surface2);padding:1px 8px}
.col-body{flex:1;padding:10px;overflow-y:auto;transition:background .15s}
.col-body.drag-over{background:rgba(240,192,64,.06);outline:1px dashed var(--accent)}
.task{background:var(--surface2);border:1px solid var(--border2);padding:12px 14px;margin-bottom:8px;cursor:grab;transition:transform .15s,border-color .15s;user-select:none}
.task:hover{border-color:var(--border);transform:translateY(-1px)}
.task.dragging{opacity:.35;cursor:grabbing}
.task-title{font-size:12px;color:var(--text);font-weight:600;margin-bottom:4px;line-height:1.4}
.task-desc{font-size:10px;color:var(--muted);line-height:1.5;margin-bottom:8px}
.task-footer{display:flex;align-items:center;justify-content:space-between}
.task-date{font-size:9px;color:var(--muted2)}
.task-actions{display:flex;gap:4px;opacity:0;transition:opacity .15s}
.task:hover .task-actions{opacity:1}
.ta-btn{background:none;border:1px solid var(--border2);color:var(--muted);padding:3px 8px;font-family:'JetBrains Mono',monospace;font-size:9px;cursor:pointer;letter-spacing:1px;transition:all .15s}
.ta-btn:hover{border-color:var(--accent);color:var(--accent)}
.ta-btn.del:hover{border-color:var(--red);color:var(--red)}
.col-inprogress .task{border-left:2px solid var(--orange)}
.col-completed .task{border-left:2px solid var(--green);opacity:.65}
.empty-col{text-align:center;padding:32px 16px;font-size:10px;color:var(--muted2);letter-spacing:1px}
.log-list{display:flex;flex-direction:column;gap:8px}
.log-entry{background:var(--surface);border:1px solid var(--border);padding:12px 16px;display:flex;align-items:center;gap:14px}
.log-time{font-size:10px;color:var(--muted);white-space:nowrap;min-width:80px}
.log-msg{font-size:11px;color:var(--text)}
.modal-overlay{position:fixed;inset:0;background:rgba(8,8,16,.9);z-index:100;display:none;align-items:center;justify-content:center}
.modal-overlay.open{display:flex}
.modal{background:var(--surface);border:1px solid var(--border);width:480px;max-width:95vw;position:relative}
.modal::before{content:'';position:absolute;top:-1px;left:20px;right:20px;height:2px;background:var(--accent)}
.modal-head{padding:20px 24px;border-bottom:1px solid var(--border);font-family:'Syne',sans-serif;font-size:14px;font-weight:700}
.modal-body{padding:24px}
.modal-field{margin-bottom:18px}
.modal-field label{display:block;font-size:9px;color:var(--muted);letter-spacing:2px;margin-bottom:8px}
.modal-field input,.modal-field textarea{width:100%;background:var(--bg);border:1px solid var(--border);color:var(--text);padding:10px 12px;font-family:'JetBrains Mono',monospace;font-size:12px;outline:none;resize:vertical}
.modal-field input:focus,.modal-field textarea:focus{border-color:var(--accent)}
.modal-footer{padding:16px 24px;border-top:1px solid var(--border);display:flex;gap:8px;justify-content:flex-end}
.m-btn{padding:10px 20px;font-family:'JetBrains Mono',monospace;font-size:11px;letter-spacing:1px;cursor:pointer;border:1px solid var(--border2);background:var(--surface2);color:var(--muted);transition:all .15s}
.m-btn:hover{border-color:var(--accent);color:var(--accent)}
.m-btn.primary{background:var(--accent);color:#080810;border-color:var(--accent);font-weight:700}
.m-btn.primary:hover{opacity:.85}
</style>
</head>
<body>
<nav class="sidebar">
  <div class="sidebar-logo">
    <div class="logo-text">VUCKOCLAW</div>
    <div class="logo-sub">AGENT DASHBOARD</div>
  </div>
  <div class="nav">
    <div class="nav-section">NAVIGATION</div>
    <div class="nav-item active" onclick="showPage('home')" id="nav-home"><span>⌂</span> ÜBERSICHT</div>
    <div class="nav-item" onclick="showPage('board')" id="nav-board"><span>◫</span> TASK BOARD <span class="nav-badge" id="badge-count">0</span></div>
    <div class="nav-item" onclick="showPage('activity')" id="nav-activity"><span>◎</span> AKTIVITÄT</div>
  </div>
  <div class="sidebar-bottom">
    <div><span class="agent-dot dot-available" id="sidebar-dot"></span><span class="agent-label" id="sidebar-status">BEREIT</span></div>
    <button class="logout-btn" onclick="location.href='/logout'">⎋ LOGOUT</button>
  </div>
</nav>
<div class="main">
  <div class="topbar">
    <div class="page-title" id="page-title">ÜBERSICHT</div>
    <div class="topbar-right"><span id="uptime-display">–</span><span id="clock">–</span></div>
  </div>
  <div class="content">

    <div class="page active" id="page-home">
      <div class="stats-grid">
        <div class="stat-card s-agent">
          <div class="stat-label">AGENT STATUS</div>
          <div style="display:flex;align-items:center;gap:10px">
            <span class="agent-dot dot-available" id="home-dot"></span>
            <span style="font-family:'Syne',sans-serif;font-size:18px;font-weight:700" id="home-status-label">BEREIT</span>
          </div>
          <div>
            <button class="ctrl-btn" onclick="setStatus('available')">BEREIT</button>
            <button class="ctrl-btn" onclick="setStatus('busy')">AKTIV</button>
            <button class="ctrl-btn" onclick="setStatus('offline')">OFFLINE</button>
          </div>
        </div>
        <div class="stat-card s-open">
          <div class="stat-label">OFFEN</div>
          <div class="stat-value" id="stat-open">–</div>
          <div class="stat-sub">backlog + in progress</div>
        </div>
        <div class="stat-card s-done">
          <div class="stat-label">ABGESCHLOSSEN</div>
          <div class="stat-value" id="stat-done">–</div>
          <div class="stat-sub">completed total</div>
        </div>
      </div>
      <div class="quick-card">
        <div style="font-size:9px;color:var(--muted);letter-spacing:2px;margin-bottom:14px">SCHNELL-TASK ERSTELLEN</div>
        <div class="add-row">
          <input class="add-input" id="quick-title" placeholder="Task Titel..." onkeydown="if(event.key==='Enter')quickAdd()">
          <input class="add-input" id="quick-desc" placeholder="Beschreibung (optional)" style="max-width:280px">
          <button class="add-btn" onclick="quickAdd()">+ TASK</button>
        </div>
      </div>
    </div>

    <div class="page" id="page-board">
      <div class="board-toolbar">
        <input class="add-input" id="board-title" placeholder="Neuer Task..." onkeydown="if(event.key==='Enter')boardAdd()">
        <input class="add-input" id="board-desc" placeholder="Beschreibung..." style="max-width:260px" onkeydown="if(event.key==='Enter')boardAdd()">
        <button class="add-btn" onclick="boardAdd()">+ HINZUFÜGEN</button>
      </div>
      <div class="board-cols">
        <div class="col col-backlog" ondragover="onDragOver(event)" ondrop="onDrop(event,'backlog')" ondragleave="onDragLeave(event)">
          <div class="col-head"><span class="col-name">BACKLOG</span><span class="col-count" id="cnt-backlog">0</span></div>
          <div class="col-body" id="list-backlog"></div>
        </div>
        <div class="col col-inprogress" ondragover="onDragOver(event)" ondrop="onDrop(event,'inProgress')" ondragleave="onDragLeave(event)">
          <div class="col-head"><span class="col-name">IN PROGRESS</span><span class="col-count" id="cnt-inprogress">0</span></div>
          <div class="col-body" id="list-inprogress"></div>
        </div>
        <div class="col col-completed" ondragover="onDragOver(event)" ondrop="onDrop(event,'completed')" ondragleave="onDragLeave(event)">
          <div class="col-head"><span class="col-name">COMPLETED</span><span class="col-count" id="cnt-completed">0</span></div>
          <div class="col-body" id="list-completed"></div>
        </div>
      </div>
    </div>

    <div class="page" id="page-activity">
      <div class="log-list" id="activity-log">
        <div style="font-size:11px;color:var(--muted);padding:20px 0">Noch keine Aktivitäten in dieser Session.</div>
      </div>
    </div>

  </div>
</div>

<div class="modal-overlay" id="edit-modal">
  <div class="modal">
    <div class="modal-head">TASK BEARBEITEN</div>
    <div class="modal-body">
      <input type="hidden" id="edit-id">
      <div class="modal-field"><label>TITEL</label><input type="text" id="edit-title"></div>
      <div class="modal-field"><label>BESCHREIBUNG</label><textarea id="edit-desc" rows="4"></textarea></div>
    </div>
    <div class="modal-footer">
      <button class="m-btn" onclick="closeModal()">ABBRECHEN</button>
      <button class="m-btn primary" onclick="saveEdit()">SPEICHERN</button>
    </div>
  </div>
</div>

<script>
let tasks = { backlog:[], inProgress:[], completed:[] };
let activityLog = [];
let dragId = null, dragFrom = null;

const pageTitles = { home:'ÜBERSICHT', board:'TASK BOARD', activity:'AKTIVITÄT' };
function showPage(name) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  document.getElementById('page-' + name).classList.add('active');
  document.getElementById('nav-' + name).classList.add('active');
  document.getElementById('page-title').textContent = pageTitles[name];
}

setInterval(() => { document.getElementById('clock').textContent = new Date().toLocaleTimeString('de-DE'); }, 1000);
document.getElementById('clock').textContent = new Date().toLocaleTimeString('de-DE');

function fmtDate(iso) { return iso ? new Date(iso).toLocaleDateString('de-DE',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'}) : ''; }
function fmtUp(s) { return Math.floor(s/3600)+'h '+Math.floor((s%3600)/60)+'m'; }
function esc(s) { return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

const dotClass = { available:'dot-available', busy:'dot-busy', offline:'dot-offline' };
const statusLabel = { available:'BEREIT', busy:'AKTIV', offline:'OFFLINE' };

async function fetchStatus() {
  try {
    const d = await (await fetch('/api/status')).json();
    const dc = dotClass[d.state]||'dot-offline';
    const lbl = statusLabel[d.state]||d.state;
    document.getElementById('home-dot').className = 'agent-dot ' + dc;
    document.getElementById('sidebar-dot').className = 'agent-dot ' + dc;
    document.getElementById('home-status-label').textContent = lbl;
    document.getElementById('sidebar-status').textContent = lbl;
    document.getElementById('uptime-display').textContent = 'UP ' + fmtUp(d.uptime);
  } catch(e) {}
}

async function setStatus(state) {
  await fetch('/api/status', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({state}) });
  addActivity('Status → ' + statusLabel[state]);
  fetchStatus();
}

async function fetchTasks() {
  try {
    tasks = await (await fetch('/api/tasks')).json();
    renderBoard();
    const open = (tasks.backlog||[]).length + (tasks.inProgress||[]).length;
    document.getElementById('stat-open').textContent = open;
    document.getElementById('stat-done').textContent = (tasks.completed||[]).length;
    document.getElementById('badge-count').textContent = open;
  } catch(e) {}
}

function renderBoard() {
  renderCol('backlog', tasks.backlog||[], 'backlog');
  renderCol('inprogress', tasks.inProgress||[], 'inProgress');
  renderCol('completed', tasks.completed||[], 'completed');
}

function renderCol(colId, list, listKey) {
  const el = document.getElementById('list-' + colId);
  document.getElementById('cnt-' + colId).textContent = list.length;
  if (!list.length) { el.innerHTML = '<div class="empty-col">— leer —</div>'; return; }
  el.innerHTML = list.map(t => {
    let actions = '';
    if (listKey === 'backlog') {
      actions = '<button class="ta-btn" onclick="openEdit(\\'' + t.id + '\\')">EDIT</button>' +
                '<button class="ta-btn" onclick="moveTask(\\'' + t.id + '\\',\\'inProgress\\')">▶</button>' +
                '<button class="ta-btn del" onclick="delTask(\\'' + t.id + '\\')">✕</button>';
    } else if (listKey === 'inProgress') {
      actions = '<button class="ta-btn" onclick="moveTask(\\'' + t.id + '\\',\\'completed\\')">✓</button>' +
                '<button class="ta-btn" onclick="moveTask(\\'' + t.id + '\\',\\'backlog\\')">↩</button>';
    } else {
      actions = '<button class="ta-btn" onclick="moveTask(\\'' + t.id + '\\',\\'backlog\\')">↩</button>' +
                '<button class="ta-btn del" onclick="delTask(\\'' + t.id + '\\')">✕</button>';
    }
    return '<div class="task" draggable="true" id="task-' + t.id + '"' +
      ' ondragstart="onDragStart(event,\\'' + t.id + '\\',\\'' + listKey + '\\')"' +
      ' ondragend="onDragEnd(event)">' +
      '<div class="task-title">' + esc(t.title) + '</div>' +
      (t.description ? '<div class="task-desc">' + esc(t.description) + '</div>' : '') +
      '<div class="task-footer"><span class="task-date">' + fmtDate(t.createdAt) + '</span>' +
      '<div class="task-actions">' + actions + '</div></div></div>';
  }).join('');
}

function onDragStart(e, id, from) {
  dragId = id; dragFrom = from;
  e.dataTransfer.effectAllowed = 'move';
  setTimeout(() => { const el = document.getElementById('task-' + id); if(el) el.classList.add('dragging'); }, 0);
}
function onDragEnd() {
  document.querySelectorAll('.task').forEach(t => t.classList.remove('dragging'));
  document.querySelectorAll('.col-body').forEach(c => c.classList.remove('drag-over'));
}
function onDragOver(e) {
  e.preventDefault();
  const body = e.currentTarget.querySelector('.col-body');
  if (body) body.classList.add('drag-over');
}
function onDragLeave(e) {
  const body = e.currentTarget.querySelector('.col-body');
  if (body) body.classList.remove('drag-over');
}
async function onDrop(e, to) {
  e.preventDefault();
  const body = e.currentTarget.querySelector('.col-body');
  if (body) body.classList.remove('drag-over');
  if (!dragId || dragFrom === to) return;
  await moveTask(dragId, to);
}

async function moveTask(id, to) {
  await fetch('/api/tasks/' + id + '/move', { method:'PATCH', headers:{'Content-Type':'application/json'}, body: JSON.stringify({to}) });
  addActivity('Task → ' + to);
  fetchTasks();
}

async function delTask(id) {
  if (!confirm('Task löschen?')) return;
  await fetch('/api/tasks/' + id, { method:'DELETE' });
  addActivity('Task gelöscht');
  fetchTasks();
}

async function addTask(title, desc) {
  if (!title?.trim()) return;
  await fetch('/api/tasks', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({title: title.trim(), description: desc||''}) });
  addActivity('Task erstellt: ' + title);
  fetchTasks();
}

function quickAdd() {
  const t = document.getElementById('quick-title').value;
  const d = document.getElementById('quick-desc').value;
  addTask(t, d);
  document.getElementById('quick-title').value = '';
  document.getElementById('quick-desc').value = '';
}

function boardAdd() {
  const t = document.getElementById('board-title').value;
  const d = document.getElementById('board-desc').value;
  addTask(t, d);
  document.getElementById('board-title').value = '';
  document.getElementById('board-desc').value = '';
}

function openEdit(id) {
  const all = [...(tasks.backlog||[]),...(tasks.inProgress||[]),...(tasks.completed||[])];
  const t = all.find(x => x.id === id);
  if (!t) return;
  document.getElementById('edit-id').value = id;
  document.getElementById('edit-title').value = t.title;
  document.getElementById('edit-desc').value = t.description||'';
  document.getElementById('edit-modal').classList.add('open');
}
function closeModal() { document.getElementById('edit-modal').classList.remove('open'); }
async function saveEdit() {
  const id = document.getElementById('edit-id').value;
  const title = document.getElementById('edit-title').value;
  const description = document.getElementById('edit-desc').value;
  await fetch('/api/tasks/' + id, { method:'PUT', headers:{'Content-Type':'application/json'}, body: JSON.stringify({title, description}) });
  addActivity('Task bearbeitet: ' + title);
  closeModal();
  fetchTasks();
}
document.getElementById('edit-modal').addEventListener('click', e => { if(e.target === e.currentTarget) closeModal(); });

function addActivity(msg) {
  const t = new Date().toLocaleTimeString('de-DE');
  activityLog.unshift({time: t, msg});
  if (activityLog.length > 100) activityLog.pop();
  const el = document.getElementById('activity-log');
  el.innerHTML = activityLog.map(e =>
    '<div class="log-entry"><span class="log-time">' + e.time + '</span><span class="log-msg">' + esc(e.msg) + '</span></div>'
  ).join('');
}

fetchStatus();
fetchTasks();
setInterval(fetchStatus, 5000);
setInterval(fetchTasks, 8000);
</script>
</body>
</html>`;

app.get('*', requireAuth, (req, res) => res.send(dashboard));

app.listen(PORT, HOST, () => {
  console.log('[VuckoClaw] http://' + HOST + ':' + PORT);
});
