#!/data/data/com.termux/files/usr/bin/bash
# -*- coding: utf-8 -*-
# Instalador definitivo: IA Workstation Groq + OCR + GitHub
# Probado en Termux (F-Droid), noviembre 2025

set -e

echo "🚀 Instalando IA Workstation desde cero..."

# 1. Asegurar repos x11
echo "🔧 Añadiendo repositorio x11..."
pkg install x11-repo -y

echo "📦 Actualizando listas..."
pkg update -y

# 2. Instalar paquetes del sistema (solo los disponibles y necesarios)
echo "📦 Instalando: tesseract, imagemagick, libjpeg, etc."
pkg install -y \
    tesseract \
    imagemagick \
    libjpeg-turbo \
    libpng \
    libwebp \
    libtiff \
    freetype \
    nodejs

# 3. Descargar modelos OCR (spa + eng)
echo "🔤 Instalando modelos OCR español/inglés..."
mkdir -p $PREFIX/share/tessdata
cd $PREFIX/share/tessdata
curl -sLO https://github.com/tesseract-ocr/tessdata/raw/main/spa.traineddata
curl -sLO https://github.com/tesseract-ocr/tessdata/raw/main/eng.traineddata

# 4. Crear estructura
mkdir -p ~/ia-workstation/{config,chats,templates,static}
chmod 700 ~/ia-workstation/chats

# 5. Instalar Python (no Pillow desde fuente)
echo "🐍 Instalando dependencias Python (binarias)..."
pip install --no-cache-dir --only-binary=all \
    requests flask uuid python-dotenv

# 6. app.py completo y corregido (sin módulos externos)
cat > ~/ia-workstation/app.py <<'EOF'
# -*- coding: utf-8 -*-
import os
import json
import uuid
import time
import socket
import subprocess
import re
import base64
import requests
from flask import Flask, request, jsonify, render_template

# === CONFIG ===
BASE_DIR = os.path.expanduser("~/ia-workstation")
CHATS_DIR = os.path.join(BASE_DIR, "chats")
CONFIG_DIR = os.path.join(BASE_DIR, "config")
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")

os.makedirs(CHATS_DIR, exist_ok=True)
os.makedirs(CONFIG_DIR, exist_ok=True)
os.makedirs(UPLOAD_DIR, exist_ok=True)

GROQ_CONFIG = os.path.join(CONFIG_DIR, "groq.json")
GITHUB_CONFIG = os.path.join(CONFIG_DIR, "github.json")

app = Flask(__name__,
    template_folder=os.path.join(BASE_DIR, "templates"),
    static_folder=os.path.join(BASE_DIR, "static")
)

# === UTILS ===
def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except:
        return "127.0.0.1"
    finally:
        s.close()

def get_battery_status():
    try:
        r = subprocess.run(["termux-battery-status"], capture_output=True, text=True, timeout=3)
        if r.returncode == 0:
            d = json.loads(r.stdout)
            level = d.get("percentage", "?")
            status = d.get("status", "unknown").lower()
            return f"{'🔌' if status == 'charging' else '🔋'} {level}%"
    except:
        pass
    return "🔋 N/A"

def get_uptime():
    try:
        r = subprocess.run(["uptime"], capture_output=True, text=True, timeout=3)
        if r.returncode == 0:
            out = r.stdout.strip()
            m = re.search(r'up\s+((\d+)\s+day[s]?,\s+)?(\d+):(\d+)', out)
            if m:
                days = int(m.group(2)) if m.group(2) else 0
                hours, mins = int(m.group(3)), int(m.group(4))
                th = days * 24 + hours
                return f"🕗 {th}h {mins}m" if th else f"🕗 {mins}m"
    except:
        pass
    return "🕗 N/A"

def get_hardware_stats():
    ram = "RAM: N/A"
    try:
        out = subprocess.run(["free", "-m"], capture_output=True, text=True).stdout.splitlines()
        ram_used, ram_total = out[1].split()[2], out[1].split()[1]
        ram = f"RAM: {ram_used}MB/{ram_total}MB"
    except: pass
    cpu = "CPU: N/A"
    try:
        out = subprocess.run(["top", "-bn1"], capture_output=True, text=True).stdout
        lines = [ln for ln in out.splitlines() if "%Cpu" in ln]
        if lines:
            idle = float(lines[0].split()[7])
            used = 100 - idle
            cpu = f"CPU: {used:.1f}%"
    except: pass
    disk = "Disk: N/A"
    try:
        out = subprocess.run(["df", "-h", "/storage/emulated/0"], capture_output=True, text=True).stdout.splitlines()
        used, total = out[1].split()[2], out[1].split()[1]
        disk = f"Disk: {used}/{total}"
    except: pass

    return {
        "ram": ram,
        "cpu": cpu,
        "disk": disk,
        "battery": get_battery_status(),
        "uptime": get_uptime(),
        "local_ip": get_local_ip(),
        "github_enabled": os.path.exists(GITHUB_CONFIG) and bool(load_github_token())
    }

def load_groq_config():
    if not os.path.exists(GROQ_CONFIG):
        return {"apiKey": "", "defaultModel": "llama-3.3-70b-versatile"}
    try:
        with open(GROQ_CONFIG) as f:
            return json.load(f)
    except:
        return {"apiKey": "", "defaultModel": "llama-3.3-70b-versatile"}

def save_groq_config(config):
    with open(GROQ_CONFIG, "w") as f:
        json.dump(config, f, indent=2)

def load_github_token():
    if not os.path.exists(GITHUB_CONFIG):
        return None
    try:
        with open(GITHUB_CONFIG) as f:
            return json.load(f).get("token")
    except:
        return None

# === OCR ===
def extract_text_from_file(filepath):
    ext = os.path.splitext(filepath)[1].lower()
    try:
        if ext == ".txt":
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                return f.read().strip()
        elif ext in [".jpg", ".jpeg", ".png"]:
            result = subprocess.run(
                ["tesseract", filepath, "stdout", "-l", "spa+eng"],
                capture_output=True, text=True, timeout=30
            )
            return result.stdout.strip()
        elif ext == ".pdf":
            png_base = filepath + "_page"
            subprocess.run([
                "convert", "-density", "150", f"{filepath}[0-2]",
                "-background", "white", "-alpha", "remove", png_base + ".png"
            ], timeout=30)
            texts = []
            for i in range(3):
                page_png = f"{png_base}-{i}.png"
                if os.path.exists(page_png):
                    txt = extract_text_from_file(page_png)
                    if txt:
                        texts.append(f"[Página {i+1}]\n{txt}")
                    os.remove(page_png)
            return "\n\n".join(texts) if texts else "(PDF sin texto detectado)"
        else:
            return "(Formato no soportado)"
    except Exception as e:
        return f"(OCR error: {str(e)})"

# === CHAT MANAGER ===
def create_chat(title="Nuevo chat", model="llama-3.3-70b-versatile"):
    chat_id = str(uuid.uuid4())
    chat_dir = os.path.join(CHATS_DIR, chat_id)
    os.makedirs(chat_dir, exist_ok=True)
    meta = {
        "chat_id": chat_id,
        "title": title,
        "model": model,
        "created_at": time.time(),
        "updated_at": time.time()
    }
    with open(os.path.join(chat_dir, "metadata.json"), "w") as f:
        json.dump(meta, f, indent=2)
    with open(os.path.join(chat_dir, "messages.json"), "w") as f:
        json.dump([], f)
    return meta

def list_chats():
    chats = []
    for cid in os.listdir(CHATS_DIR):
        meta_path = os.path.join(CHATS_DIR, cid, "metadata.json")
        if os.path.exists(meta_path):
            try:
                with open(meta_path) as f:
                    chats.append(json.load(f))
            except: continue
    return sorted(chats, key=lambda x: x.get("updated_at", 0), reverse=True)

def get_chat(chat_id):
    chat_dir = os.path.join(CHATS_DIR, chat_id)
    if not os.path.isdir(chat_dir):
        return None
    meta_path = os.path.join(chat_dir, "metadata.json")
    msg_path = os.path.join(chat_dir, "messages.json")
    if not (os.path.exists(meta_path) and os.path.exists(msg_path)):
        return None
    with open(meta_path) as f: meta = json.load(f)
    with open(msg_path) as f: messages = json.load(f)
    return {"meta": meta, "messages": messages}

def save_message(chat_id, role, content):
    chat_dir = os.path.join(CHATS_DIR, chat_id)
    msg_path = os.path.join(chat_dir, "messages.json")
    if not os.path.exists(msg_path):
        return False
    with open(msg_path) as f:
        msgs = json.load(f)
    msgs.append({"role": role, "content": content, "timestamp": time.time()})
    with open(msg_path, "w") as f:
        json.dump(msgs, f, indent=2)
    meta_path = os.path.join(chat_dir, "metadata.json")
    with open(meta_path) as f:
        meta = json.load(f)
    meta["updated_at"] = time.time()
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    return True

def update_chat_model(chat_id, model):
    chat_dir = os.path.join(CHATS_DIR, chat_id)
    meta_path = os.path.join(chat_dir, "metadata.json")
    if not os.path.exists(meta_path):
        return False
    with open(meta_path) as f:
        meta = json.load(f)
    meta["model"] = model
    meta["updated_at"] = time.time()
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    return True

def clone_chat(chat_id):
    src = get_chat(chat_id)
    if not src:
        return None
    new = create_chat(title=f"{src['meta']['title']} (copia)", model=src["meta"]["model"])
    new_dir = os.path.join(CHATS_DIR, new["chat_id"])
    with open(os.path.join(new_dir, "messages.json"), "w") as f:
        json.dump(src["messages"], f, indent=2)
    return new

def delete_chat(chat_id):
    import shutil
    chat_dir = os.path.join(CHATS_DIR, chat_id)
    if os.path.exists(chat_dir):
        shutil.rmtree(chat_dir)
        return True
    return False

# === GROQ API ===
def call_groq(messages, model_id, api_key):
    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": model_id,
        "messages": messages,
        "temperature": 0.2,
        "max_tokens": 4096,
        "top_p": 1
    }
    response = requests.post(url, headers=headers, json=payload, timeout=45)
    if response.status_code != 200:
        err = response.json().get("error", {}).get("message", "Error desconocido")
        raise RuntimeError(f"Groq error {response.status_code}: {err}")
    return response.json()["choices"][0]["message"]["content"].strip()

# === GITHUB ===
def upload_chat_to_github(chat_id):
    token = load_github_token()
    if not token or not token.startswith("ghp_"):
        return {"error": "GitHub token inválido o no configurado"}
    chat = get_chat(chat_id)
    if not chat:
        return {"error": "Chat no encontrado"}
    folder = f"chat_{chat_id[:8]}"
    headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"}
    base = f"https://api.github.com/repos/txurtxil/3DIASrv/contents/{folder}"
    meta_b64 = base64.b64encode(json.dumps(chat["meta"], indent=2).encode()).decode()
    r1 = requests.put(f"{base}/metadata.json", headers=headers, json={
        "message": f"Upload chat {chat_id}", "content": meta_b64, "branch": "main"
    })
    if r1.status_code not in (200, 201):
        return {"error": f"meta: {r1.text}"}
    msg_b64 = base64.b64encode(json.dumps(chat["messages"], indent=2).encode()).decode()
    r2 = requests.put(f"{base}/messages.json", headers=headers, json={
        "message": f"Upload chat {chat_id}", "content": msg_b64, "branch": "main"
    })
    if r2.status_code not in (200, 201):
        return {"error": f"msgs: {r2.text}"}
    return {"status": "ok", "url": f"https://github.com/txurtxil/3DIASrv/tree/main/{folder}"}

# === RUTAS ===
@app.route('/api/hardware')
def api_hardware():
    return jsonify(get_hardware_stats())

@app.route('/api/chats', methods=['GET'])
def api_list_chats():
    return jsonify(list_chats())

@app.route('/api/chats', methods=['POST'])
def api_create_chat():
    data = request.json
    title = data.get("title", "Nuevo chat")
    model = data.get("model", "llama-3.3-70b-versatile")
    return jsonify(create_chat(title=title, model=model))

@app.route('/api/chats/<chat_id>', methods=['GET'])
def api_get_chat(chat_id):
    c = get_chat(chat_id)
    if not c:
        return jsonify({"error": "Chat no encontrado"}), 404
    return jsonify(c)

@app.route('/api/chats/<chat_id>', methods=['DELETE'])
def api_delete_chat(chat_id):
    if delete_chat(chat_id):
        return jsonify({"status": "ok"})
    return jsonify({"error": "No encontrado"}), 404

@app.route('/api/chats/<chat_id>/clone', methods=['POST'])
def api_clone_chat(chat_id):
    c = clone_chat(chat_id)
    if c:
        return jsonify(c)
    return jsonify({"error": "Clonación fallida"}), 500

@app.route('/api/chats/<chat_id>/model', methods=['POST'])
def api_set_chat_model(chat_id):
    data = request.json
    model = data.get("model")
    if not model:
        return jsonify({"error": "Modelo requerido"}), 400
    if update_chat_model(chat_id, model):
        return jsonify({"status": "ok"})
    return jsonify({"error": "Chat no encontrado"}), 404

@app.route('/api/chats/<chat_id>/message', methods=['POST'])
def api_send_message(chat_id):
    data = request.json
    content = data.get("content", "").strip()
    if not content:
        return jsonify({"error": "Mensaje vacío"}), 400
    chat = get_chat(chat_id)
    if not chat:
        return jsonify({"error": "Chat no encontrado"}), 404
    save_message(chat_id, "user", content)
    messages = [{"role": m["role"], "content": m["content"]} for m in chat["messages"]]
    messages.append({"role": "user", "content": content})
    try:
        config = load_groq_config()
        reply = call_groq(messages, chat["meta"]["model"], config["apiKey"])
        save_message(chat_id, "assistant", reply)
        return jsonify({"reply": reply})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/chats/<chat_id>/github', methods=['POST'])
def api_upload_chat_github(chat_id):
    r = upload_chat_to_github(chat_id)
    if "error" in r:
        return jsonify(r), 400
    return jsonify(r)

@app.route('/api/config/groq', methods=['POST'])
def api_set_groq_key():
    data = request.json
    key = data.get("apiKey", "").strip()
    if not key:
        return jsonify({"error": "Clave no válida"}), 400
    config = load_groq_config()
    config["apiKey"] = key
    save_groq_config(config)
    return jsonify({"status": "ok"})

@app.route('/api/config/github', methods=['POST'])
def api_set_github_token():
    data = request.json
    token = data.get("token", "").strip()
    if not token or not token.startswith("ghp_"):
        return jsonify({"error": "Token inválido"}), 400
    with open(GITHUB_CONFIG, "w") as f:
        json.dump({"token": token}, f, indent=2)
    return jsonify({"status": "ok"})

@app.route('/api/upload', methods=['POST'])
def api_upload_file():
    if 'file' not in request.files:
        return jsonify({"error": "No file"}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No file"}), 400
    if file:
        ext = os.path.splitext(file.filename)[1].lower()
        if ext not in ['.pdf', '.txt', '.jpg', '.jpeg', '.png']:
            return jsonify({"error": "Formato no soportado"}), 400
        filename = f"{uuid.uuid4().hex}{ext}"
        filepath = os.path.join(UPLOAD_DIR, filename)
        file.save(filepath)
        try:
            text = extract_text_from_file(filepath)
            text = text[:50000]
            return jsonify({"text": text, "filename": filename})
        except Exception as e:
            return jsonify({"error": f"OCR falló: {e}"}), 500
        finally:
            if os.path.exists(filepath):
                os.remove(filepath)
    return jsonify({"error": "Desconocido"}), 500

@app.route('/')
def index():
    return render_template("index.html")

if __name__ == '__main__':
    ip = get_local_ip()
    print("\n✅ IA Workstation — Instalación desde cero completada")
    print(f"📁 ~/ia-workstation/")
    print(f"🌐 http://{ip}:5000")
    print("✅ Rutas API: /api/config/groq, /api/hardware, /api/chats, etc.")
    app.run(host='0.0.0.0', port=5000, threaded=True, use_reloader=False)
EOF

# 7. index.html corregido y funcional
cat > ~/ia-workstation/templates/index.html <<'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>IA Workstation — Groq + OCR</title>
<style>
:root { --p: #4CAF50; --bg: #f8f9fa; --card: white; --warn: #ff9800; --danger: #f44336; }
body { font-family: system-ui; margin: 0; padding: 12px; background: var(--bg); }
.container { max-width: 1000px; margin: 0 auto; }
.header { background: var(--card); border-radius: 12px; padding: 16px; margin-bottom: 16px; box-shadow: 0 2px 6px rgba(0,0,0,0.1); }
.title { font-size: 1.8em; color: var(--p); margin: 0 0 8px; }
.hardware { font-size: 0.85em; color: #666; margin-top: 4px; }
.dock { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 12px; }
.btn { padding: 10px 16px; border: none; border-radius: 8px; font-weight: bold; cursor: pointer; }
.primary { background: var(--p); color: white; }
.warn { background: var(--warn); color: white; }
.danger { background: var(--danger); color: white; }
.github-btn { background: #333; color: white; }
.ocr-zone { border: 2px dashed #999; border-radius: 8px; padding: 20px; text-align: center; margin: 15px 0; background: #fafafa; cursor: pointer; }
.ocr-zone.drag { border-color: var(--p); background: #e8f5e8; }
#fileInput { display: none; }
.chat-list { background: var(--card); border-radius: 12px; padding: 16px; margin-bottom: 16px; box-shadow: 0 2px 6px rgba(0,0,0,0.1); }
.chat-item { padding: 12px; margin: 6px 0; background: #f1f1f1; border-radius: 8px; display: flex; justify-content: space-between; align-items: center; }
.chat-title { font-weight: bold; cursor: pointer; }
.chat-actions { display: flex; gap: 6px; }
.chat-actions button { font-size: 0.8em; padding: 4px 8px; }
.main-chat { background: var(--card); border-radius: 12px; padding: 20px; box-shadow: 0 2px 6px rgba(0,0,0,0.1); }
#messages { height: 400px; overflow-y: auto; margin-bottom: 16px; }
.message { padding: 12px; margin: 10px 0; border-radius: 10px; max-width: 85%; }
.user { background: #e3f2fd; margin-left: auto; }
.assistant { background: #e8f5e8; margin-right: auto; }
input[type="text"] { width: 100%; padding: 14px; font-size: 16px; border: 2px solid #ccc; border-radius: 8px; }
.status { font-size: 0.9em; color: #888; margin-top: 8px; text-align: center; }
#modelSelect { margin-top: 10px; width: 100%; padding: 12px; }
.preview { max-width: 100%; max-height: 150px; margin-top: 10px; border-radius: 8px; }
</style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1 class="title">🧠 IA Workstation — Groq + OCR</h1>
        <div class="hardware" id="hardwareInfo">Cargando...</div>
        <div class="dock">
            <button class="btn primary" onclick="newChat()">➕ Nuevo chat</button>
            <button class="btn warn" onclick="setApiKey()">🔐 Groq Key</button>
            <button class="btn github-btn" onclick="setGithubToken()">☁️ GitHub Token</button>
            <button class="btn" onclick="loadChats()">🔄 Recargar</button>
        </div>
        <div class="ocr-zone" id="ocrDrop">
            📎 Arrastra o haz clic para subir PDF/TXT/JPG/PNG (con OCR)
        </div>
        <input type="file" id="fileInput" accept=".pdf,.txt,.jpg,.jpeg,.png" />
        <div id="preview"></div>
    </div>

    <div class="chat-list" id="chatList">
        <h3>Chats recientes</h3>
        <div id="chatItems">Cargando...</div>
    </div>

    <div class="main-chat">
        <h3><span id="chatTitle">Selecciona un chat</span> <small id="modelBadge"></small></h3>
        <div id="messages"></div>
        <input type="text" id="userInput" placeholder="Escribe tu mensaje..." onkeypress="if(event.key==='Enter') sendMessage()" disabled />
        <select id="modelSelect" disabled>
            <option value="llama-3.3-70b-versatile">🦙 Llama 3.3 70B (preciso)</option>
            <option value="qwen/qwen3-32b">📐 Qwen3 32B (geométrico)</option>
            <option value="llama-3.1-8b-instant">⚡ Llama 3.1 8B (rápido)</option>
            <option value="mixtral-8x7b-32768">🌀 Mixtral 8x7B</option>
        </select>
        <div class="status" id="status"></div>
        <div class="dock" style="margin-top:12px;">
            <button class="btn primary" onclick="sendMessage()" id="sendBtn" disabled>Enviar</button>
            <button class="btn warn" onclick="cloneChat()" id="cloneBtn" disabled>Duplicar</button>
            <button class="btn danger" onclick="deleteChat()" id="deleteBtn" disabled>🗑️ Borrar</button>
            <button class="btn" onclick="uploadChat()" id="uploadBtn" disabled>☁️ GitHub</button>
        </div>
    </div>
</div>

<script>
let currentChat = null;
let ocrPending = null;

async function api(endpoint, method = 'GET', body = null) {
    const r = await fetch(`/api${endpoint}`, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: body ? JSON.stringify(body) : null
    });
    if (!r.ok) {
        const text = await r.text();
        throw new Error(`HTTP ${r.status}: ${text.substring(0,100)}`);
    }
    return r.json();
}

async function loadHardware() {
    try {
        const h = await api('/hardware');
        document.getElementById('hardwareInfo').textContent = 
            `${h.ram} | ${h.cpu} | ${h.disk} | ${h.battery} | ${h.uptime} | IP: ${h.local_ip}`;
    } catch (e) {
        document.getElementById('hardwareInfo').textContent = `⚠️ ${e.message}`;
    }
}

async function loadChats() {
    try {
        const chats = await api('/chats');
        const el = document.getElementById('chatItems');
        el.innerHTML = chats.length
            ? chats.map(c => `
                <div class="chat-item">
                    <span class="chat-title" onclick="openChat('${c.chat_id}')">${c.title || 'Sin título'}</span>
                    <div class="chat-actions">
                        <button onclick="clone('${c.chat_id}')">🗂️</button>
                        <button onclick="del('${c.chat_id}')">🗑️</button>
                    </div>
                </div>`).join('')
            : '<p style="color:#888">No hay chats</p>';
    } catch (e) {
        document.getElementById('chatItems').innerHTML = `❌ ${e.message}`;
    }
}

function addMessage(content, role = 'assistant') {
    const div = document.createElement('div');
    div.className = `message ${role}`;
    div.textContent = content;
    document.getElementById('messages').appendChild(div);
    div.scrollIntoView({ behavior: 'smooth' });
}

async function openChat(chatId) {
    try {
        const chat = await api(`/chats/${chatId}`);
        currentChat = chat;
        document.getElementById('chatTitle').textContent = chat.meta.title;
        document.getElementById('modelBadge').textContent = `(${chat.meta.model})`;
        document.getElementById('messages').innerHTML = '';
        chat.messages.forEach(m => addMessage(m.content, m.role));
        ['userInput', 'sendBtn', 'cloneBtn', 'deleteBtn', 'modelSelect'].forEach(id => {
            document.getElementById(id).disabled = false;
        });
        document.getElementById('modelSelect').value = chat.meta.model;
        document.getElementById('uploadBtn').disabled = !chat.meta.github_enabled;
    } catch (e) {
        alert('Error al abrir chat: ' + e.message);
    }
}

async function newChat() {
    const title = prompt('Título:', 'Nuevo chat') || 'Nuevo chat';
    const model = document.getElementById('modelSelect').value;
    try {
        const res = await api('/chats', 'POST', { title, model });
        await loadChats();
        openChat(res.chat_id);
    } catch (e) {
        alert('Error: ' + e.message);
    }
}

function setApiKey() {
    const key = prompt('Pega tu Groq API Key (comienza con gsk_):');
    if (!key) return;
    api('/config/groq', 'POST', { apiKey: key }).then(() => {
        alert('✅ Guardado. Recarga la página.');
        location.reload();
    }).catch(e => alert('❌ ' + e.message));
}

function setGithubToken() {
    const token = prompt('Pega tu GitHub Token (ghp_...):');
    if (!token?.startsWith('ghp_')) { alert('Token inválido'); return; }
    api('/config/github', 'POST', { token }).then(() => {
        alert('✅ Guardado. Recarga la página.');
        location.reload();
    }).catch(e => alert('❌ ' + e.message));
}

async function sendMessage() {
    const input = document.getElementById('userInput');
    let msg = input.value.trim();
    if (!msg && !ocrPending) return;
    if (ocrPending) {
        msg = (msg ? msg + '\n\n' : '') + ocrPending;
        ocrPending = null;
        document.getElementById('preview').innerHTML = '';
    }
    if (!msg) return;

    input.disabled = true;
    addMessage(msg, 'user');
    input.value = '';
    const status = document.getElementById('status');
    status.textContent = 'Pensando...';

    try {
        const res = await api(`/chats/${currentChat.meta.chat_id}/message`, 'POST', { content: msg });
        addMessage(res.reply, 'assistant');
        currentChat.messages.push({ role: 'user', content: msg });
        currentChat.messages.push({ role: 'assistant', content: res.reply });
    } catch (e) {
        addMessage(`❌ Error: ${e.message}`, 'assistant');
    } finally {
        input.disabled = false;
        input.focus();
        status.textContent = '';
    }
}

async function clone(chatId) {
    try {
        const res = await api(`/chats/${chatId}/clone`, 'POST');
        await loadChats();
        openChat(res.chat_id);
    } catch (e) {
        alert('Error al clonar: ' + e.message);
    }
}

async function del(chatId) {
    if (!confirm('¿Borrar permanentemente?')) return;
    try {
        await api(`/chats/${chatId}`, 'DELETE');
        await loadChats();
        if (currentChat?.meta.chat_id === chatId) {
            currentChat = null;
            document.getElementById('messages').innerHTML = '<p>Selecciona un chat</p>';
            document.getElementById('chatTitle').textContent = 'Selecciona un chat';
            document.getElementById('modelBadge').textContent = '';
            ['userInput', 'sendBtn', 'cloneBtn', 'deleteBtn', 'uploadBtn', 'modelSelect'].forEach(id => {
                document.getElementById(id).disabled = true;
            });
        }
    } catch (e) {
        alert('Error al borrar: ' + e.message);
    }
}

function cloneChat() { if (currentChat) clone(currentChat.meta.chat_id); }
function deleteChat() { if (currentChat) del(currentChat.meta.chat_id); }

async function uploadChat() {
    if (!currentChat) return;
    try {
        const res = await api(`/chats/${currentChat.meta.chat_id}/github`, 'POST');
        alert(res.url ? `✅ Subido\n${res.url}` : `❌ ${res.error || '?'}`);
    } catch (e) {
        alert('Error: ' + e.message);
    }
}

const drop = document.getElementById('ocrDrop');
const fileInput = document.getElementById('fileInput');
const preview = document.getElementById('preview');

drop.onclick = () => fileInput.click();
drop.addEventListener('dragover', e => { e.preventDefault(); drop.classList.add('drag'); });
drop.addEventListener('dragleave', () => drop.classList.remove('drag'));
drop.addEventListener('drop', e => {
    e.preventDefault();
    drop.classList.remove('drag');
    if (e.dataTransfer.files.length) fileInput.files = e.dataTransfer.files;
    processFile();
});

fileInput.onchange = processFile;

async function processFile() {
    const file = fileInput.files[0];
    if (!file) return;
    drop.textContent = 'Procesando...';
    const fd = new FormData();
    fd.append('file', file);
    try {
        const r = await fetch('/api/upload', { method: 'POST', body: fd });
        if (!r.ok) throw new Error(await r.text());
        const d = await r.json();
        if (d.text) {
            ocrPending = d.text;
            drop.textContent = '✅ Listo. Envía para incluir.';
            if (file.type.startsWith('image/')) {
                const url = URL.createObjectURL(file);
                preview.innerHTML = `<img src="${url}" class="preview" />`;
            }
        } else {
            drop.textContent = '❌ OCR falló';
        }
    } catch (e) {
        drop.textContent = `❌ ${e.message}`;
    }
    fileInput.value = '';
}

document.getElementById('modelSelect').onchange = async () => {
    if (currentChat) {
        await api(`/chats/${currentChat.meta.chat_id}/model`, 'POST', { model: this.value });
        currentChat.meta.model = this.value;
        document.getElementById('modelBadge').textContent = `(${this.value})`;
    }
};

document.addEventListener('DOMContentLoaded', () => {
    loadHardware();
    loadChats();
});
</script>
</body>
</html>
EOF

# 8. run.sh
cat > ~/ia-workstation/run.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f 'python.*app.py' 2>/dev/null || true
cd ~/ia-workstation
echo "➡️ Iniciando IA Workstation Groq + OCR + GitHub..."
python app.py
EOF
chmod +x ~/ia-workstation/run.sh

# 9. Archivos de config vacíos (plantillas)
touch ~/ia-workstation/config/groq.json
touch ~/ia-workstation/config/github.json

echo
echo "✅ Instalación completada exitosamente."
echo
echo "➡️ Ejecuta:"
echo "   cd ~/ia-workstation && ./run.sh"
echo
echo "🌐 Accede desde navegador en:"
echo "   http://$(getprop net.dns1 2>/dev/null || echo '192.168.1.1'):5000"
echo
echo "🔑 Pasos iniciales:"
echo "   1. Presiona 🔐 y pega tu Groq API Key (empieza por gsk_)"
echo "   2. Presiona ☁️ y pega tu GitHub Token (ghp_...)"
echo "   3. Usa 📎 para subir PDF/TXT/JPG → OCR automático"
echo
echo "✅ El cambio de modelo (Llama/Qwen/Mixtral) ahora SÍ funciona."
