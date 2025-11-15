#!/data/data/com.termux/files/usr/bin/bash
# -*- coding: utf-8 -*-
# ==========================================
# 🚀 IA WORKSTATION v4.4 - SECURE MULTIMODAL
# ==========================================
# MEJORAS:
# 1. ¡NUEVO! Al adjuntar una imagen, se muestra una miniatura clicable.
# 2. ¡NUEVO! Añadido botón '❌' para cancelar un adjunto.
# 3. 'messages.json' ahora guarda el nombre del adjunto.
# ==========================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Iniciando instalación de IA Workstation v4.4...${NC}"

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
rm -f ~/ia-workstation/static/sw.js
rm -f ~/ia-workstation/static/manifest.json

# 5. Configurar Entorno Virtual (VENV)
echo -e "${GREEN}🐍 Creando entorno virtual Python (limpio)...${NC}"
rm -rf venv 
python -m venv venv 

echo -e "${GREEN}🐍 Instalando librerías Python (con BasicAuth)...${NC}"
./venv/bin/pip install --upgrade pip
./venv/bin/pip install --no-cache-dir \
    requests \
    flask \
    flask-basicauth \
    uuid \
    python-dotenv \
    certifi

# 6. Escribir backend (app.py) v4.4
echo -e "${BLUE}📝 Escribiendo aplicación (app.py) v4.4...${NC}"
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
import getpass
from flask import Flask, request, jsonify, render_template, send_from_directory, after_this_request
from flask_basicauth import BasicAuth
from werkzeug.security import generate_password_hash, check_password_hash

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
AUTH_CONFIG = os.path.join(CONFIG_DIR, "auth.json")

app = Flask(__name__,
    template_folder=os.path.join(BASE_DIR, "templates"),
    static_folder=os.path.join(BASE_DIR, "static")
)

# === CONFIGURACIÓN DE AUTH ===
def setup_auth():
    if not os.path.exists(AUTH_CONFIG):
        print("--- 🔐 Configuración de Seguridad (Primera vez) ---")
        print("Crea un usuario y contraseña para acceder a la web.")
        print("Si olvidas esto, borra 'config/auth.json' y reinicia.")
        username = input("Nombre de usuario: ")
        password = getpass.getpass("Contraseña: ")
        hashed_pw = generate_password_hash(password)
        auth_data = {"username": username, "password_hash": hashed_pw}
        with open(AUTH_CONFIG, "w") as f:
            json.dump(auth_data, f)
        print(f"✅ Usuario '{username}' creado.")
        return auth_data
    else:
        with open(AUTH_CONFIG) as f:
            return json.load(f)

auth_data = setup_auth()

app.config['BASIC_AUTH_USERNAME'] = auth_data['username']
app.config['BASIC_AUTH_PASSWORD'] = 'dummy_password'
basic_auth = BasicAuth(app)

def verify_custom_credentials(username, password):
    if username == auth_data["username"] and \
       check_password_hash(auth_data["password_hash"], password):
        return True
    return False

basic_auth.check_credentials = verify_custom_credentials
# --- FIN DE AUTH ---


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
@basic_auth.required
def r_info():
    battery = "N/A"; ram = "RAM: N/A"; disk = "Disk: N/A"
    try:
        r = subprocess.run(["termux-battery-status"], capture_output=True, text=True, timeout=2)
        if r.returncode == 0:
            d = json.loads(r.stdout)
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
    payload = {"model": model, "messages": [sys_msg] + messages, "temperature": 0.3, "max_tokens": 8192}
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

def call_gemini(messages, model, key, user_prompt_text, image_file=None):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
    
    contents = convert_to_gemini_contents(messages)
    
    new_user_parts = [{"text": user_prompt_text}]
    if image_file:
        try:
            image_bytes = image_file.read()
            image_b64 = base64.b64encode(image_bytes).decode('utf-8')
            new_user_parts.append({
                "inline_data": {
                    "mime_type": image_file.mimetype,
                    "data": image_b64
                }
            })
        except Exception as e:
            raise Exception(f"Error al procesar la imagen: {str(e)}")
            
    contents.append({"role": "user", "parts": new_user_parts})

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

# === RUTAS API (Protegidas) ===
@app.route('/api/chats', methods=['GET', 'POST'])
@basic_auth.required
def r_chats():
    if request.method == 'POST':
        d = request.json
        model = d.get("model") or "llama-3.3-70b-versatile"
        return jsonify(create_chat(d.get("title", "Chat"), model))
    return jsonify(list_chats())

@app.route('/api/chats/<cid>', methods=['GET', 'DELETE'])
@basic_auth.required
def r_chat_detail(cid):
    if request.method == 'DELETE':
        import shutil
        shutil.rmtree(os.path.join(CHATS_DIR, cid), ignore_errors=True)
        return jsonify({"status": "deleted"})
    c = get_chat(cid); return jsonify(c) if c else (jsonify({"error": "404"}), 404)

@app.route('/api/chats/<cid>/model', methods=['POST'])
@basic_auth.required
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
@basic_auth.required
def r_message(cid):
    c = get_chat(cid);
    if not c: return jsonify({"error": "Chat no encontrado"}), 404
    
    content = request.json.get("content", "");
    if not content: return jsonify({"error": "Vacío"}), 400
    
    c["messages"].append({"role": "user", "content": content, "ts": time.time(), "attachment": None})
    with open(os.path.join(CHATS_DIR, cid, "messages.json"), "w") as f: json.dump(c["messages"], f)
    
    try:
        api_msgs = [{"role": m["role"], "content": m["content"]} for m in c["messages"]]
        model_id = c["meta"]["model"]
        reply = ""

        if model_id.startswith("gemini-"):
            cfg = load_gemini_config()
            api_key = cfg.get("apiKey")
            if not api_key: return jsonify({"error": "Falta API Key de Gemini"}), 403
            reply = call_gemini(api_msgs[:-1], model_id, api_key, user_prompt_text=content, image_file=None)
        
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

@app.route('/api/chats/<cid>/message_vision', methods=['POST'])
@basic_auth.required
def r_message_vision(cid):
    c = get_chat(cid)
    if not c: return jsonify({"error": "Chat no encontrado"}), 404
    
    model_id = c["meta"]["model"]
    if not model_id.startswith("gemini-"):
        return jsonify({"error": "Solo los modelos Gemini soportan imágenes."}), 400
        
    content = request.form.get("content", "")
    file = request.files.get("file")
    
    if not file:
        return jsonify({"error": "No se recibió ningún archivo de imagen."}), 400
    
    # --- ¡CAMBIO v4.4! (Guardar nombre de archivo) ---
    c["messages"].append({"role": "user", "content": content, "ts": time.time(), "attachment": file.filename})
    with open(os.path.join(CHATS_DIR, cid, "messages.json"), "w") as f: json.dump(c["messages"], f)
    
    try:
        api_msgs = [{"role": m["role"], "content": m["content"]} for m in c["messages"]]
        cfg = load_gemini_config()
        api_key = cfg.get("apiKey")
        if not api_key: return jsonify({"error": "Falta API Key de Gemini"}), 403

        reply = call_gemini(api_msgs[:-1], model_id, api_key, user_prompt_text=content, image_file=file)

        c["messages"].append({"role": "assistant", "content": reply, "ts": time.time()})
        with open(os.path.join(CHATS_DIR, cid, "messages.json"), "w") as f: json.dump(c["messages"], f)
        c["meta"]["updated_at"] = time.time()
        with open(os.path.join(CHATS_DIR, cid, "metadata.json"), "w") as f: json.dump(c["meta"], f)
        
        return jsonify({"reply": reply})

    except Exception as e:
        logging.exception("Error en r_message_vision")
        return jsonify({"error": str(e)}), 500

@app.route('/api/chats/<cid>/github', methods=['POST'])
@basic_auth.required
def r_github_upload(cid):
    result = upload_chat_to_github(cid)
    if "error" in result: return jsonify(result), 400
    return jsonify(result)

@app.route('/api/config', methods=['POST'])
@basic_auth.required
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
@basic_auth.required
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
@basic_auth.required
def r_compile_scad():
    code = request.json.get("code")
 
