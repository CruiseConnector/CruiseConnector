/**
 * VuckoClaw Dashboard - Script
 * Queue-Logik, Task-Management, Context-Speicher
 */

const API_URL = window.location.origin;

let currentEditTask = null;
let currentEditColumn = null;

// Navigation
document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', () => {
        document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
        document.querySelectorAll('.dashboard-section').forEach(s => s.classList.remove('active'));
        
        item.classList.add('active');
        const section = item.dataset.section;
        document.getElementById(section).classList.add('active');
        
        if (section === 'activities') {
            loadTasks();
        } else if (section === 'context') {
            loadContextFiles();
        } else if (section === 'dashboard') {
            loadStats();
        }
    });
});

// Stats laden
async function loadStats() {
    try {
        const res = await fetch(`${API_URL}/api/stats`);
        const stats = await res.json();
        
        document.getElementById('stat-total').textContent = stats.total;
        document.getElementById('stat-progress').textContent = stats.inProgress;
        document.getElementById('stat-completed').textContent = stats.completed;
    } catch (err) {
        console.error('Stats error:', err);
    }
}

// Tasks laden
async function loadTasks() {
    try {
        const res = await fetch(`${API_URL}/api/tasks`);
        const data = await res.json();
        
        renderColumn('backlog', data.backlog);
        renderColumn('progress', data.inProgress);
        renderColumn('completed', data.completed);
        
        document.getElementById('count-backlog').textContent = data.backlog.length;
        document.getElementById('count-progress').textContent = data.inProgress.length;
        document.getElementById('count-completed').textContent = data.completed.length;
    } catch (err) {
        console.error('Tasks error:', err);
    }
}

// Spalte rendern
function renderColumn(column, tasks) {
    const container = document.getElementById(`${column}-list`);
    container.innerHTML = '';
    
    tasks.forEach(task => {
        const card = document.createElement('div');
        card.className = 'task-card';
        
        // Verschiebe-Buttons je nach Spalte
        let moveButtons = '';
        if (column === 'backlog') {
            moveButtons = `<button class="task-btn" onclick="moveTask('${task.id}', 'backlog', 'progress')" title="Starten">▶</button>`;
        } else if (column === 'progress') {
            moveButtons = `
                <button class="task-btn" onclick="moveTask('${task.id}', 'progress', 'backlog')" title="Zurück zu Backlog">◀</button>
                <button class="task-btn" onclick="moveTask('${task.id}', 'progress', 'completed')" title="Abschließen">✓</button>
            `;
        } else if (column === 'completed') {
            moveButtons = `
                <button class="task-btn" onclick="moveTask('${task.id}', 'completed', 'progress')" title="Wieder öffnen">↺</button>
                <button class="task-btn" onclick="moveTask('${task.id}', 'completed', 'backlog')" title="Zurück zu Backlog">◀</button>
            `;
        }
        
        card.innerHTML = `
            <div class="task-title">${escapeHtml(task.title)}</div>
            <div class="task-desc">${escapeHtml(task.description || '')}</div>
            <div class="task-actions">
                ${moveButtons}
                <button class="task-btn" onclick="editTask('${task.id}', '${column}')" title="Bearbeiten">✎</button>
                <button class="task-btn delete" onclick="deleteTask('${task.id}', '${column}')" title="Löschen">×</button>
            </div>
        `;
        container.appendChild(card);
    });
}

// Task Modal öffnen
function openTaskModal(task = null, column = null) {
    currentEditTask = task;
    currentEditColumn = column;
    
    document.getElementById('modalTitle').textContent = task ? 'Task bearbeiten' : 'Neue Task';
    document.getElementById('taskTitle').value = task ? task.title : '';
    document.getElementById('taskDesc').value = task ? task.description : '';
    
    document.getElementById('taskModal').classList.add('active');
}

function closeTaskModal() {
    document.getElementById('taskModal').classList.remove('active');
    currentEditTask = null;
    currentEditColumn = null;
}

// Task speichern
document.getElementById('taskForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const title = document.getElementById('taskTitle').value;
    const description = document.getElementById('taskDesc').value;
    
    try {
        if (currentEditTask) {
            await fetch(`${API_URL}/api/tasks/${currentEditTask.id}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ title, description, column: currentEditColumn })
            });
        } else {
            await fetch(`${API_URL}/api/tasks`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ title, description, column: 'backlog' })
            });
        }
        
        closeTaskModal();
        loadTasks();
        loadStats();
    } catch (err) {
        console.error('Save error:', err);
        alert('Fehler beim Speichern');
    }
});

// Task bearbeiten
async function editTask(id, column) {
    try {
        const res = await fetch(`${API_URL}/api/tasks`);
        const data = await res.json();
        const task = data[column].find(t => t.id === id);
        
        if (task) {
            openTaskModal(task, column);
        }
    } catch (err) {
        console.error('Edit error:', err);
    }
}

// Task löschen
async function deleteTask(id, column) {
    if (!confirm('Task wirklich löschen?')) return;
    
    try {
        await fetch(`${API_URL}/api/tasks/${id}?column=${column}`, {
            method: 'DELETE'
        });
        
        loadTasks();
        loadStats();
    } catch (err) {
        console.error('Delete error:', err);
    }
}

// Task verschieben
async function moveTask(id, from, to) {
    console.log(`Moving task ${id} from ${from} to ${to}`);
    try {
        const response = await fetch(`${API_URL}/api/tasks/${id}/move`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ from, to })
        });
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const result = await response.json();
        console.log('Move successful:', result);
        
        // Sofort neu laden
        await loadTasks();
        await loadStats();
    } catch (err) {
        console.error('Move error:', err);
        alert('Fehler beim Verschieben: ' + err.message);
    }
}

// GO - Queue ausführen
async function executeQueue() {
    if (!confirm('Alle Tasks in "In Progress" ausführen?')) return;
    
    try {
        const res = await fetch(`${API_URL}/api/go`, {
            method: 'POST'
        });
        
        const result = await res.json();
        
        if (result.success) {
            alert(`✓ ${result.message}`);
        } else {
            alert(result.message);
        }
        
        loadTasks();
        loadStats();
    } catch (err) {
        console.error('GO error:', err);
    }
}

// Context Files laden
async function loadContextFiles() {
    try {
        const res = await fetch(`${API_URL}/api/context`);
        const files = await res.json();
        
        const container = document.getElementById('context-grid');
        container.innerHTML = '';
        
        const icons = {
            'AGENTS.md': '👤',
            'IDENTITY.md': '🎭',
            'SOUL.md': '🔥',
            'USER.md': '👤',
            'MEMORY.md': '🧠',
            'BOOTSTRAP.md': '🚀',
            'HEARTBEAT.md': '💓'
        };
        
        files.forEach(file => {
            const card = document.createElement('div');
            card.className = 'context-card';
            card.innerHTML = `
                <div class="context-header">
                    <div class="context-name">
                        <span>${icons[file.name] || '📄'}</span>
                        ${file.name}
                    </div>
                    <div class="context-status ${file.exists ? 'exists' : 'missing'}"></div>
                </div>
                <div class="context-body">
                    <div class="context-info">
                        ${file.exists 
                            ? `Größe: ${formatBytes(file.size)}` 
                            : 'Datei existiert nicht'}
                    </div>
                    <button class="context-btn" onclick="openContextFile('${file.name}')">
                        ${file.exists ? 'Bearbeiten' : 'Erstellen'}
                    </button>
                </div>
            `;
            container.appendChild(card);
        });
    } catch (err) {
        console.error('Context error:', err);
    }
}

// Context File öffnen
async function openContextFile(filename) {
    try {
        const res = await fetch(`${API_URL}/api/context/${filename}`);
        const data = await res.json();
        
        const content = prompt(`Inhalt von ${filename}:`, data.content);
        
        if (content !== null) {
            await fetch(`${API_URL}/api/context/${filename}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ content })
            });
            
            loadContextFiles();
        }
    } catch (err) {
        console.error('Context edit error:', err);
    }
}

// Utilities
function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

// Initial load
loadStats();
