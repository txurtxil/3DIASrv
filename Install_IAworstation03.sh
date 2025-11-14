#!/data/data/com.termux/files/usr/bin/bash
# -*- coding: utf-8 -*-
# ==========================================
# 🚀 IA WORKSTATION v3.8 - INSTALADOR
# ==========================================
# CORRECCIÓN:
# 1. Aumentado 'maxOutputTokens' de Gemini a 8192.
# 2. Eliminado el icono de batería (solo muestra %).
# ==========================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Iniciando instalación de IA Workstation v3.8...${NC}"

# 1. Configurar Repositorios y Actualizar
echo -e "${GREEN}📦 Configurando repositorios...${NC}"
pkg update -y
pkg install x11-repo -y

# 2. Instalar Dependencias del Sistema
echo -e "${GREEN}📦 Instalando paquetes (Versión limpia)...${NC}"
pkg install -y \
    python \
    python-pip \
    tesseract \
    imagemagick \
    poppler \
    openscad \
    libjpeg-turbo \
    libpng \
    freetype \
    nodejs \
    git \
    rust \
    binutils \
    ca-certificates

# 3. Descargar Modelos OCR
echo -e "${GREEN}🔤 Configurando OCR Tesseract...${NC}"
mkdir -p $PREFIX/share/tessdata
cd $PREFIX/share/tessdata
if [ ! -f "spa.traineddata" ]; then
    curl -sLO https://github.com/tesseract-ocr/tessdata/raw/main/spa.traineddata
fi
if [ ! -f "eng.traineddata" ]; then
    curl -sLO https://github.com/tesseract-ocr/tessdata/raw/main/eng.traineddata
fi

# 4. Crear Estructura de Carpetas
echo -e "${GREEN}📂 Creando directorio de trabajo ~/ia-workstation...${NC}"
cd ~
mkdir -p ~/ia-workstation/{config,chats,templates,static,uploads,stl_exports}
cd ~/ia-workstation

# Forzar limpieza de archivos antiguos
rm -f ~/ia-workstation/app.py
rm -f ~/ia-workstation/templates/index.html

# 5. Configurar Entorno Virtual (VENV)
echo -e "${GREEN}🐍 Creando entorno virtual Python (limpio)...${NC}"
rm -rf venv 
python -m venv venv # <-- Venv limpio

echo -e "${GREEN}🐍 Instalando librerías Python (solo las básicas)...${NC}"
./venv/bin/pip install --upgrade pip
./venv/bin/pip install --no-cache-dir \
    requests \
    flask \
    uuid \
    python-dotenv \
    certifi

# 6. Escribir backend (app.py) v3.8
echo -e "${BLUE}📝 Escribiendo aplicación (app.py) v3.8...${NC}"
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
import logging
from flask import Flask, request, jsonify, render_template, send_from_directory, after_this_request

# === CONFIG ===
BASE_DIR = os.path.expanduser("~/ia-workstation")
CHATS_DIR = os.path.join(BASE_DIR, "chats")
CONFIG_DIR = os.path.join(BASE_DIR, "config")
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
STL_DIR = os.path.join(BASE_DIR, "stl_exports")
os.makedirs(CHATS_DIR, exist_ok=True)
os.makedirs(CONFIG_DIR, exist_ok=True)
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(STL_DIR, exist_ok=True)
GROQ_CONFIG = os.path.join(CONFIG_DIR, "groq.json")
GITHUB_CONFIG = os.path.join(CONFIG_DIR, "github.json")
GEMINI_CONFIG = os.path.join(CONFIG_DIR, "gemini.json")

app = Flask(__name__,
    template_folder=os.path.join(BASE_DIR, "templates"),
    static_folder=os.path.join(BASE_DIR, "static")
)

# === UTILS (Cargadores de Config) ===
def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try: s.connect(("8.8.8.8", 80)); return s.getsockname()[0]
    except: return "127.0.0.1"
    finally: s.close()

def load_groq_config():
    default = {"apiKey": ""}
    if not os.path.exists(GROQ_CONFIG): return default
    try:
        with open(GROQ_CONFIG) as f: return json.load(f)
    except: return default

def load_gemini_config():
    default = {"apiKey": ""}
    if not os.path.exists(GEMINI_CONFIG): return default
    try:
        with open(GEMINI_CONFIG) as f: return json.load(f)
    except: return default

def load_github_token():
    if not os.path.exists(GITHUB_CONFIG): return None
    try:
        with open(GITHUB_CONFIG) as f: return json.load(f).get("token")
    except: return None

@app.route('/api/info')
def r_info():
    battery = "N/A"; ram = "RAM: N/A"; disk = "Disk: N/A"
    try:
        r = subprocess.run(["termux-battery-status"], capture_output=True, text=True, timeout=2)
        if r.returncode == 0:
            d = json.loads(r.stdout)
            # --- ¡CORRECCIÓN v3.8! (Sin icono) ---
            battery = f"{d.get('percentage', '?')}%"
    except: pass
    try:
        out = subprocess.run(["free", "-m"], capture_output=True, text=True, timeout=2).stdout.splitlines()
        if len(out) > 1: ram = f"RAM: {out[1].split()[2]}/{out[1].split()[1]} MB"
    except: pass
    try:
        out = subprocess.run(["df", "-h", BASE_DIR], capture_output=True, text=True, timeout=2).stdout.splitlines()
        if len(out) > 1:
            parts = out[1].split()
            disk = f"Disk: {parts[2]}/{parts[1]}"
    except: pass
    return jsonify({
        "ram": ram, "battery": battery, "disk": disk, "local_ip": get_local_ip(),
        "github_enabled": bool(load_github_token())
    })

# === OCR OPTIMIZADO ===
def extract_text_from_file(filepath):
    ext = os.path.splitext(filepath)[1].lower()
    try:
        if ext == ".txt":
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f: return f.read().strip()
        elif ext in [".jpg", ".jpeg", ".png"]:
            res = subprocess.run(["tesseract", filepath, "stdout", "-l", "spa+eng"], capture_output=True, text=True, timeout=45)
            return res.stdout.strip()
        elif ext == ".pdf":
            base_name = filepath.replace(".pdf", "")
            subprocess.run(["pdftoppm", "-jpeg", "-f", "1", "-l", "3", "-r", "150", filepath, base_name], timeout=45)
            texts = []
            for i in range(1, 4):
                page_img = f"{base_name}-{i}.jpg"
                if os.path.exists(page_img):
                    txt = extract_text_from_file(page_img)
                    if txt: texts.append(f"[Página {i}]\n{txt}")
                    os.remove(page_img)
            return "\n\n".join(texts) if texts else "(PDF sin texto legible)"
        return "(Formato no soportado)"
    except Exception as e: return f"(Error OCR: {str(e)})"

# === CHAT CORE ===
def get_chat(chat_id):
    chat_dir = os.path.join(CHATS_DIR, chat_id)
    if not os.path.exists(chat_dir): return None
    try:
        with open(os.path.join(chat_dir, "metadata.json")) as f: meta = json.load(f)
        with open(os.path.join(chat_dir, "messages.json")) as f: msgs = json.load(f)
        return {"meta": meta, "messages": msgs}
    except: return None

def create_chat(title, model):
    cid = str(uuid.uuid4())
    cdir = os.path.join(CHATS_DIR, cid)
    os.makedirs(cdir, exist_ok=True)
    meta = {"chat_id": cid, "title": title, "model": model, "updated_at": time.time()}
    with open(os.path.join(cdir, "metadata.json"), "w") as f: json.dump(meta, f)
    with open(os.path.join(cdir, "messages.json"), "w") as f: json.dump([], f)
    return meta

def list_chats():
    chats = []
    for cid in os.listdir(CHATS_DIR):
        try:
            with open(os.path.join(CHATS_DIR, cid, "metadata.json")) as f:
                chats.append(json.load(f))
        except: continue
    return sorted(chats, key=lambda x: x.get("updated_at", 0), reverse=True)

# --- CLIENTE DE API 1: GROQ ---
def call_groq(messages, model, key):
    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    sys_msg = {"role": "system", "content": "Responde siempre usando Markdown. Para código (Python, OpenSCAD, C++, etc.), usa bloques de código con el nombre del lenguaje."}
    payload = {"model": model, "messages": [sys_msg] + messages, "temperature": 0.3, "max_tokens": 8192} # Aumentado por si acaso
    r = requests.post(url, headers=headers, json=payload, timeout=60) 
    if r.status_code != 200: 
        raise Exception(f"Groq API Error ({r.status_code}): {r.text}")
    return r.json()["choices"][0]["message"]["content"]

# --- CLIENTE DE API 2: GEMINI (API REST) ---
def convert_to_gemini_contents(messages):
    contents = []
    system_prompt = "Responde siempre usando Markdown. Para código (Python, OpenSCAD, C++, etc.), usa bloques de código con el nombre del lenguaje."
    for msg in messages:
        role = "model" if msg["role"] == "assistant" else "user"
        if contents and contents[-1]["role"] == "user" and role == "user":
            contents[-1]["parts"][0]["text"] += "\n\n" + msg["content"]
        else:
            contents.append({"role": role, "parts": [{"text": msg["content"]}]})
    if contents and contents[0]["role"] == "user":
        contents[0]["parts"][0]["text"] = f"{system_prompt}\n\n---\n\n{contents[0]['parts'][0]['text']}"
    return contents

def call_gemini(messages, model, key):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
    contents = convert_to_gemini_contents(messages)
    
    # --- ¡CORRECCIÓN v3.8! (Aumentado a 8192) ---
    payload = {
        "contents": contents,
        "generationConfig": { "temperature": 0.3, "maxOutputTokens": 8192 }
    }
    
    try:
        r = requests.post(url, json=payload, timeout=60)
        r.raise_for_status()
        response_data = r.json()
        
        if "candidates" not in response_data:
            if "error" in response_data:
                raise Exception(f"Error de API Gemini: {response_data['error']['message']}")
            raise Exception("Respuesta de Gemini inválida (sin 'candidates').")

        candidate = response_data["candidates"][0]
        
        if "finishReason" in candidate and candidate["finishReason"] != "STOP":
            # Si la razón es MAX_TOKENS, el texto parcial puede estar presente
            if candidate["finishReason"] == "MAX_TOKENS" and "content" in candidate:
                 return candidate["content"]["parts"][0]["text"] + "\n\n[FIN DE RESPUESTA: LÍMITE DE TOKENS ALCANZADO]"
            raise Exception(f"Respuesta de Gemini bloqueada (Razón: {candidate['finishReason']})")
        
        if "content" not in candidate or "parts" not in candidate["content"]:
            raise Exception("Respuesta de Gemini recibida, pero está vacía (KeyError: 'parts').")
        
        return candidate["content"]["parts"][0]["text"]

    except requests.exceptions.HTTPError as http_err:
        logging.error(f"Error HTTP en Gemini: {http_err.response.text}")
        raise Exception(f"Error en API de Gemini: {http_err.response.text}")
    except Exception as e:
        logging.error(f"Error en API de Gemini: {e}")
        raise Exception(f"Error en API de Gemini: {str(e)}")

# === GITHUB ===
def upload_chat_to_github(chat_id):
    token = load_github_token()
    if not token: return {"error": "GitHub token no configurado"}
    chat = get_chat(chat_id);
    if not chat: return {"error": "Chat no encontrado"}
    repo = "txurtxil/3DIASrv"; folder = f"chat_{chat_id[:8]}"
    headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"}
    base = f"https://api.github.com/repos/{repo}/contents/{folder}"
    meta_b64 = base64.b64encode(json.dumps(chat["meta"], indent=2).encode()).decode()
    r1 = requests.put(f"{base}/metadata.json", headers=headers, json={"message": f"Upload {chat_id}", "content": meta_b64})
    if r1.status_code not in (200, 201): return {"error": f"Error metadata: {r1.text}"}
    msg_b64 = base64.b64encode(json.dumps(chat["messages"], indent=2).encode()).decode()
    r2 = requests.put(f"{base}/messages.json", headers=headers, json={"message": f"Upload {chat_id}", "content": msg_b64})
    if r2.status_code not in (200, 201): return {"error": f"Error messages: {r2.text}"}
    return {"status": "ok", "url": f"https://github.com/{repo}/tree/main/{folder}"}

# === RUTAS API ===
@app.route('/api/chats', methods=['GET', 'POST'])
def r_chats():
    if request.method == 'POST':
        d = request.json
        model = d.get("model") or "llama-3.3-70b-versatile"
        return jsonify(create_chat(d.get("title", "Chat"), model))
    return jsonify(list_chats())

@app.route('/api/chats/<cid>', methods=['GET', 'DELETE'])
def r_chat_detail(cid):
    if request.method == 'DELETE':
        import shutil
        shutil.rmtree(os.path.join(CHATS_DIR, cid), ignore_errors=True)
        return jsonify({"status": "deleted"})
    c = get_chat(cid); return jsonify(c) if c else (jsonify({"error": "404"}), 404)

@app.route('/api/chats/<cid>/model', methods=['POST'])
def r_chat_model(cid):
    c = get_chat(cid)
    if not c: return jsonify({"error": "Chat no encontrado"}), 404
    model = request.json.get("model")
    if not model: return jsonify({"error": "Modelo no especificado"}), 400
    c["meta"]["model"] = model; c["meta"]["updated_at"] = time.time()
    try:
        with open(os.path.join(CHATS_DIR, cid, "metadata.json"), "w") as f:
            json.dump(c["meta"], f)
        return jsonify({"status": "ok", "model": model})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/chats/<cid>/message', methods=['POST'])
def r_message(cid):
    c = get_chat(cid);
    if not c: return jsonify({"error": "Chat no encontrado"}), 404
    
    content = request.json.get("content", "");
    if not content: return jsonify({"error": "Vacío"}), 400
    
    c["messages"].append({"role": "user", "content": content, "ts": time.time()})
    with open(os.path.join(CHATS_DIR, cid, "messages.json"), "w") as f: json.dump(c["messages"], f)
    
    try:
        api_msgs = [{"role": m["role"], "content": m["content"]} for m in c["messages"]]
        model_id = c["meta"]["model"]
        reply = ""

        if model_id.startswith("gemini-"):
            cfg = load_gemini_config()
            api_key = cfg.get("apiKey")
            if not api_key: return jsonify({"error": "Falta API Key de Gemini"}), 403
            reply = call_gemini(api_msgs, model_id, api_key)
        
        else:
            cfg = load_groq_config()
            api_key = cfg.get("apiKey")
            if not api_key: return jsonify({"error": "Falta API Key de Groq"}), 403
            reply = call_groq(api_msgs, model_id, api_key)

        c["messages"].append({"role": "assistant", "content": reply, "ts": time.time()})
        with open(os.path.join(CHATS_DIR, cid, "messages.json"), "w") as f: json.dump(c["messages"], f)
        c["meta"]["updated_at"] = time.time()
        with open(os.path.join(CHATS_DIR, cid, "metadata.json"), "w") as f: json.dump(c["meta"], f)
        
        return jsonify({"reply": reply})

    except Exception as e: 
        logging.exception("Error en r_message")
        return jsonify({"error": str(e)}), 500

@app.route('/api/chats/<cid>/github', methods=['POST'])
def r_github_upload(cid):
    result = upload_chat_to_github(cid)
    if "error" in result: return jsonify(result), 400
    return jsonify(result)

@app.route('/api/config', methods=['POST'])
def r_config():
    d = request.json
    if "groqApiKey" in d:
        cfg = load_groq_config(); cfg["apiKey"] = d["groqApiKey"]
        with open(GROQ_CONFIG, "w") as f: json.dump(cfg, f)
    if "geminiApiKey" in d:
        cfg_g = load_gemini_config(); cfg_g["apiKey"] = d["geminiApiKey"]
        with open(GEMINI_CONFIG, "w") as f: json.dump(cfg_g, f)
    if "githubToken" in d:
        with open(GITHUB_CONFIG, "w") as f: json.dump({"token": d["githubToken"]}, f)
    return jsonify({"status": "ok"})

@app.route('/api/upload', methods=['POST'])
def r_upload():
    f = request.files.get('file');
    if not f: return jsonify({"error": "No file"}), 400
    fname = f"{uuid.uuid4().hex}_{f.filename}"; fpath = os.path.join(UPLOAD_DIR, fname); f.save(fpath)
    try:
        text = extract_text_from_file(fpath); return jsonify({"text": text[:60000]})
    except Exception as e: return jsonify({"error": str(e)}), 500
    finally:
        if os.path.exists(fpath): os.remove(fpath)

@app.route('/api/compile_scad', methods=['POST'])
def r_compile_scad():
    code = request.json.get("code")
    if not code:
        return jsonify({"error": "No code provided"}), 400
    
    fname = uuid.uuid4().hex
    scad_path = os.path.join(STL_DIR, f"{fname}.scad"); stl_path = os.path.join(STL_DIR, f"{fname}.stl")
    
    try:
        with open(scad_path, "w", encoding="utf-8") as f: f.write(code)
        env = os.environ.copy(); env['LC_ALL'] = 'C'
        
        res = subprocess.run(["openscad", "-o", stl_path, scad_path], 
                             timeout=None, capture_output=True, text=True, env=env)
        
        if res.returncode != 0:
            stderr = res.stderr.strip(); clean_error = "Error desconocido de OpenSCAD."
            for line in stderr.splitlines():
                if line.startswith("ERROR: Parser error") or line.startswith("ERROR: Syntax error"):
                    clean_error = line; break
            if clean_error == "Error desconocido de OpenSCAD." and stderr:
                clean_error = stderr.splitlines()[-1]
            return jsonify({"error": f"{clean_error}"}), 500
        
        if os.path.exists(stl_path):
            return jsonify({"status": "ok", "download_url": f"/api/download_stl/{fname}.stl"})
        else:
            return jsonify({"error": "STL file not created (unknown error)"}), 500
    
    except subprocess.TimeoutExpired:
        return jsonify({"error": "La compilación de OpenSCAD tardó demasiado y fue cancelada."}), 500
    except Exception as e: 
        return jsonify({"error": str(e)}), 500
    finally:
        if os.path.exists(scad_path): os.remove(scad_path)

@app.route('/api/download_stl/<filename>')
def r_download_stl(filename):
    @after_this_request
    def cleanup(response):
        try: os.remove(os.path.join(STL_DIR, filename))
        except: pass
        return response
    return send_from_directory(STL_DIR, filename, as_attachment=True)

@app.route('/')
def index(): return render_template("index.html")

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    print(f"\n✅ Servidor v3.8 (Multi-API) iniciado en: http://{get_local_ip()}:5000")
    app.run(host='0.0.0.0', port=5000, threaded=True)
EOF

# 7. Escribir frontend (index.html) v3.8
echo -e "${BLUE}📝 Escribiendo interfaz (index.html) v3.8...${NC}"
cat > ~/ia-workstation/templates/index.html <<'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>IA Workstation v3.8</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css">
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>

<style>
:root { --bg: #1e1e1e; --card: #2d2d2d; --text: #e0e0e0; --acc: #4CAF50; --blue: #2196F3; }
body { background: var(--bg); color: var(--text); font-family: sans-serif; margin:0; padding:10px; }
.box { background: var(--card); padding: 15px; border-radius: 12px; margin-bottom: 15px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
h1, h3 { margin: 0 0 10px 0; color: var(--acc); }
button { padding: 8px 12px; border-radius: 6px; border: none; cursor: pointer; font-weight: bold; margin: 0 5px 5px 0; }
.btn-p { background: var(--acc); color: white; }
.btn-s { background: #555; color: white; }
.btn-gh { background: #333; color: white; }
.btn-gemini { background: #4285F4; color: white; }
input[type="text"], select { 
    width: 100%; padding: 10px; box-sizing: border-box; 
    border-radius: 6px; border: 1px solid #444; 
    background: #333; color: white; 
}
select { margin-top: 10px; }
#hw { font-size:0.8em; color:#aaa; min-height: 1em; }

/* Chat Area */
#messages { height: 50vh; overflow-y: auto; padding: 10px; border: 1px solid #444; border-radius: 8px; margin-bottom: 10px; background: #252526; }
.msg { padding: 10px; margin: 8px 0; border-radius: 8px; max-width: 95%; word-wrap: break-word; }
.msg.user { background: #3a3a3a; margin-left: auto; border-right: 3px solid var(--acc); }
.msg.assistant { background: #2d2d30; margin-right: auto; border-left: 3px solid var(--blue); }

/* Código y Botón Copiar */
.msg pre { position: relative; background: #1a1a1a; padding: 30px 10px 10px 10px; border-radius: 6px; overflow-x: auto; }
.msg code { font-family: monospace; }
.msg p { margin: 5px 0; }
.code-btn {
    position: absolute; top: 5px; background: #444; color: white;
    padding: 4px 8px; border-radius: 4px; cursor: pointer; font-size: 0.8em; border:none;
}
.copy-btn { right: 5px; }
.scad-btn { right: 70px; background: #ff6600; }
.code-btn:hover { background: #555; }

/* Sidebar */
.chat-row { display: flex; justify-content: space-between; padding: 8px; background: #333; margin-bottom: 4px; border-radius: 4px; }
.chat-row span { cursor: pointer; }
</style>
</head>
<body>

<div class="box">
    <h1>🧠 IA Workstation v3.8</h1>
    <div id="hw">Cargando hardware...</div>
    <div style="margin-top:10px;">
        <button class="btn-p" onclick="newChat()">➕ Nuevo</button>
        <button class="btn-s" onclick="askKey('groq')">🔐 Groq Key</button>
        <button class="btn-gemini" onclick="askKey('gemini')">🤖 Gemini Key</button>
        <button class="btn-gh" onclick="askKey('github')">☁️ GitHub Token</button>
        <button class="btn-s" onclick="document.getElementById('fileIn').click()">📎 OCR PDF/IMG</button>
    </div>
    <input type="file" id="fileIn" hidden onchange="uploadFile()" accept=".pdf,.jpg,.png,.txt">
    <div id="ocrPreview" style="font-size:0.8em; color:var(--acc); margin-top:5px;"></div>
</div>

<div id="mainUI" style="display:none;">
    <div class="box">
        <h3 id="cTitle">Chat</h3>
        <button class="btn-gh" id="ghUploadBtn" onclick="uploadChat()" style="float:right; margin-top:-40px; display:none;">Subir a GitHub</button>
        <div id="messages"></div>
        <div style="display:flex; gap:5px;">
            <input type="text" id="uIn" placeholder="Mensaje..." onkeypress="if(event.key==='Enter') send()">
            <button class="btn-p" onclick="send()">Enviar</button>
        </div>
        <select id="modelSelect" onchange="changeModel()">
            <option value="llama-3.3-70b-versatile">🦙 Llama 3.3 70B (Groq)</option>
            <option value="gemini-2.5-pro">🤖 Gemini 2.5 Pro (Google)</option>
            <option value="qwen/qwen3-32b">📐 Qwen3 32B (Groq)</option>
            <option value="openai/gpt-oss-120b">🌎 GPT-OSS 120B (Groq)</option>
            <option value="llama-3.1-8b-instant">⚡ Llama 3.1 8B (Groq)</option>
        </select>
    </div>
</div>

<div class="box">
    <h3>Historial</h3>
    <div id="chatList">Cargando chats...</div>
</div>

<script>
let currChat = null;
let ocrText = "";
let githubReady = false;

const $ = id => document.getElementById(id);

const api = async (u, m = 'GET', d = null) => {
    const opt = { method: m, headers: { 'Content-Type': 'application/json' } };
    if (d) opt.body = JSON.stringify(d);
    const r = await fetch('/api' + u, opt);
    const responseText = await r.text();
    let responseData = null;
    try {
        responseData = JSON.parse(responseText);
    } catch (e) {
        if (!r.ok) {
            throw new Error(responseText.substring(0, 200) || `Error HTTP ${r.status}`);
        }
    }
    if (!r.ok) {
        if (responseData && responseData.error) {
            throw new Error(responseData.error);
        }
        throw new Error(responseText.substring(0, 200) || `Error HTTP ${r.status}`);
    }
    return responseData;
};

marked.setOptions({
    highlight: (code, lang) => {
        const language = highlight.getLanguage(lang) ? lang : 'plaintext';
        return highlight.highlight(code, { language }).value;
    }
});

async function init() {
    api('/info').then(hw => {
        $('hw').textContent = `${hw.ram} | ${hw.battery} | ${hw.disk} | IP: ${hw.local_ip}`;
        githubReady = hw.github_enabled;
    }).catch(e => {
        $('hw').textContent = `⚠️ Error hardware (no crítico)`;
    });
    loadChats();
}

async function loadChats() {
    try {
        const chats = await api('/chats');
        const list = $('chatList');
        list.innerHTML = chats.length ? '' : 'No hay chats.';
        chats.forEach(c => {
            list.innerHTML += `
                <div class="chat-row">
                    <span onclick="loadChat('${c.chat_id}')" style="flex-grow:1">${c.title}</span>
                    <span onclick="delChat('${c.chat_id}')">🗑️</span>
                </div>`;
        });
    } catch(e) {
        $('chatList').innerHTML = `Error cargando chats: ${e.message}`;
    }
}

async function newChat() {
    const t = prompt("Nombre del chat:");
    if(!t) return;
    const model = $('modelSelect').value;
    try {
        const r = await api('/chats', 'POST', {title: t, model: model});
        loadChat(r.chat_id);
        loadChats();
    } catch(e) { alert(`Error al crear chat: ${e.message}`); }
}

async function loadChat(cid) {
    try {
        const c = await api(`/chats/${cid}`);
        if(!c || c.error) return;
        currChat = cid;
        $('cTitle').textContent = c.meta.title;
        $('messages').innerHTML = '';
        c.messages.forEach(m => appendMsg(m.role, m.content));
        $('mainUI').style.display = 'block';
        $('ghUploadBtn').style.display = githubReady ? 'block' : 'none';
        $('modelSelect').value = c.meta.model;
    } catch(e) { alert(`Error al cargar chat: ${e.message}`); }
}

async function changeModel() {
    if (!currChat) return;
    const newModel = $('modelSelect').value;
    try {
        await api(`/chats/${currChat}/model`, 'POST', { model: newModel });
    } catch (e) {
        alert(`Error al cambiar de modelo: ${e.message}`);
    }
}

function appendMsg(role, text) {
    const d = document.createElement('div');
    d.className = `msg ${role}`;
    if (role === 'assistant') {
        d.innerHTML = marked.parse(text);
        d.querySelectorAll('pre').forEach(pre => {
            const code = pre.querySelector('code');
            const codeText = code.innerText;
            const copyBtn = document.createElement('button');
            copyBtn.className = 'code-btn copy-btn';
            copyBtn.textContent = 'Copiar';
            copyBtn.onclick = () => {
                const ta = document.createElement('textarea');
                ta.style.position = 'absolute'; ta.style.left = '-9999px';
                ta.value = codeText;
                document.body.appendChild(ta);
                ta.select();
                try { document.execCommand('copy'); copyBtn.textContent = '¡Copiado!'; }
                catch (e) { copyBtn.textContent = 'Error'; }
                document.body.removeChild(ta);
                setTimeout(() => { copyBtn.textContent = 'Copiar'; }, 2000);
            };
            pre.appendChild(copyBtn);
            const lang = code.className || '';
            if (lang.includes('openscad') || lang.includes('scad')) {
                const scadBtn = document.createElement('button');
                scadBtn.className = 'code-btn scad-btn';
                scadBtn.textContent = 'Compilar STL';
                scadBtn.onclick = () => { compileScad(codeText, scadBtn); };
                pre.appendChild(scadBtn);
            }
        });
    } else { d.textContent = text; }
    $('messages').appendChild(d);
    d.scrollIntoView();
}

async function send() {
    const txt = $('uIn').value.trim();
    if((!txt && !ocrText) || !currChat) return;
    
    const finalTxt = ocrText ? (txt + "\n\n[Contexto Archivo]:\n" + ocrText) : txt;
    ocrText = ""; $('ocrPreview').textContent = "";
    $('uIn').value = '';
    appendMsg('user', finalTxt);
    
    const thinking = document.createElement('div');
    thinking.className = 'msg assistant'; thinking.textContent = '...';
    $('messages').appendChild(thinking);

    try {
        const r = await api(`/chats/${currChat}/message`, 'POST', {content: finalTxt});
        $('messages').removeChild(thinking);
        appendMsg('assistant', r.reply);
    } catch(e) { 
        thinking.textContent = `Error: ${e.message}`;
    }
}

async function uploadFile() {
    const f = $('fileIn').files[0];
    if(!f) return;
    $('ocrPreview').textContent = "⏳ Procesando OCR... espera...";
    const fd = new FormData(); fd.append('file', f);
    try {
        const r = await fetch('/api/upload', {method:'POST', body:fd});
        const d = await r.json();
        if(d.text) {
            ocrText = d.text;
            $('ocrPreview').textContent = "✅ Texto capturado. Se enviará con tu próximo mensaje.";
        } else { $('ocrPreview').textContent = `❌ Error OCR: ${d.error || ''}`; }
    } catch(e) { alert(e); }
}

async function askKey(type) {
    let payload = {};
    if(type === 'groq') {
        const k = prompt("Groq API Key (gsk_...):");
        if(k) payload = {groqApiKey: k};
        else return;
    } else if (type === 'gemini') {
        const k = prompt("Google AI Studio API Key:");
        if(k) payload = {geminiApiKey: k};
        else return;
    } else if (type === 'github') {
        const k = prompt("GitHub Token (ghp_...):");
        if(k && k.startsWith('ghp_')) {
            payload = {githubToken: k};
        } else if (k) { alert("Token inválido. Debe empezar con ghp_"); return; }
        else return;
    }
    
    try {
        await api('/config', 'POST', payload);
        if (type === 'github') {
             githubReady = true;
             alert("Token guardado. El botón de subida se activará en los chats.");
        } else {
             alert("API Key guardada.");
        }
    } catch(e) { alert(`Error al guardar: ${e.message}`); }
}

async function uploadChat() {
    if(!currChat || !githubReady) return;
    $('ghUploadBtn').textContent = 'Subiendo...';
    try {
        const r = await api(`/chats/${currChat}/github`, 'POST');
        if(r.url) { alert('Éxito! Subido a:\n' + r.url); }
        else { alert('Error: ' + (r.error || 'Error desconocido')); }
    } catch(e) { alert('Error: ' + e.message); }
    $('ghUploadBtn').textContent = 'Subir a GitHub';
}

async function delChat(cid) {
    if(confirm("¿Borrar?")) {
        await api(`/chats/${cid}`, 'DELETE');
        if(currChat === cid) { $('mainUI').style.display = 'none'; currChat=null; }
        loadChats();
    }
}

async function compileScad(code, btn) {
    btn.textContent = 'Compilando...';
    try {
        const r = await api('/compile_scad', 'POST', { code: code });
        if (r.download_url) {
            window.location.href = r.download_url;
            btn.textContent = '¡Descargado!';
        } else {
            btn.textContent = 'Error';
            alert(`Error de compilación: ${r.error || 'Desconocido'}`);
        }
    } catch (e) {
        btn.textContent = 'Error';
        alert(`Error de API: ${e.message}`);
    }
    setTimeout(() => { btn.textContent = 'Compilar STL'; }, 3000);
}

init();
</script>
</body>
</html>
EOF

# 8. Script de arranque (run.sh) usando VENV
echo -e "${BLUE}⚙️ Creando script de arranque (run.sh)...${NC}"
cat > ~/ia-workstation/run.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/ia-workstation
# Activar entorno virtual antes de ejecutar
source venv/bin/activate
echo "➡️ Iniciando Servidor v3.8 (Multi-API)..."
python app.py
EOF
chmod +x ~/ia-workstation/run.sh

# 9. Configuración inicial vacía
touch ~/ia-workstation/config/groq.json
touch ~/ia-workstation/config/github.json
touch ~/ia-workstation/config/gemini.json

echo
echo -e "${GREEN}✅ INSTALACIÓN COMPLETADA CON ÉXITO v3.8 ${NC}"
echo
echo -e "Correcciones:"
echo -e "  - 🐞 Eliminado SDK de Google. Se usa API REST (0 compilación)."
echo -e "  - ⏰ Eliminado el timeout de 60s en OpenSCAD."
echo -e "  - 📈 Aumentado el límite de tokens de Gemini a 8192."
echo -e "  - 🔋 Batería ahora muestra solo el porcentaje."
echo
echo -e "Para iniciar, ejecuta:"
echo -e "${BLUE}  cd ~/ia-workstation && ./run.sh${NC}"

