#!/data/data/com.termux/files/usr/bin/bash
# -*- coding: utf-8 -*-
# ==========================================
# 🚀 IA WORKSTATION v4.7.1 - DEEPSEEK + GROQ DINÁMICO
# ==========================================
# MEJORAS v4.7.1:
# 1. ✅ Botón "Enviar Imagen" abre selector completo (Cámara/Galería/Archivos)
# 2. ✅ Botón "Modelos" pide la lista a la API de Groq
# 3. ✅ Lista de modelos de respaldo actualizada (Qwen, Mixtral)
# 4. ✅ DeepSeek API gratuita integrada
# ==========================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Iniciando instalación de IA Workstation v4.7.1 (Selector de cámara corregido)...${NC}"

# 1. Configurar Repositorios y Actualizar
echo -e "${GREEN}📦 Configurando repoo...${NC}"
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

# 6. Escribir backend (app.py) v4.7.1 (Groq Dinámico)
echo -e "${BLUE}📝 Escribiendo aplicación (app.py) v4.7.1 con Groq Dinámico...${NC}"
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

# Silenciar logs de requests para no saturar la consola con polls
logging.getLogger("requests").setLevel(logging.WARNING)
logging.getLogger("urllib3").setLevel(logging.WARNING)

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
DEEPSEEK_CONFIG = os.path.join(CONFIG_DIR, "deepseek.json")
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

def load_deepseek_config():
    default = {"apiKey": ""}
    if not os.path.exists(DEEPSEEK_CONFIG): return default
    try:
        with open(DEEPSEEK_CONFIG) as f: return json.load(f)
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
    
    deepseek_cfg = load_deepseek_config()
    deepseek_enabled = bool(deepseek_cfg.get("apiKey"))
    
    return jsonify({
        "ram": ram, "battery": battery, "disk": disk, "local_ip": get_local_ip(),
        "github_enabled": bool(load_github_token()),
        "deepseek_enabled": deepseek_enabled
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
        if http_err.response.status_code == 404:
            error_data = http_err.response.json()
            if "models/" in error_data.get("error", {}).get("message", ""):
                raise Exception(f"Modelo Gemini no encontrado: {model}. Verifica que el nombre del modelo sea correcto.")
        raise Exception(f"Error en API de Gemini: {http_err.response.text}")
    except Exception as e:
        logging.error(f"Error en API de Gemini: {e}")
        raise Exception(f"Error en API de Gemini: {str(e)}")

# --- CLIENTE DE API 3: GROQ VISION ---
def encode_image_to_base64(image_file):
    """Convierte imagen a base64 para APIs"""
    try:
        image_bytes = image_file.read()
        return base64.b64encode(image_bytes).decode('utf-8')
    except Exception as e:
        raise Exception(f"Error al procesar imagen: {str(e)}")

def call_groq_vision(messages, model, key, user_prompt_text, image_file=None):
    """Llama a Groq API con soporte para imágenes"""
    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    
    # Mensaje del sistema
    sys_msg = {"role": "system", "content": "Responde siempre usando Markdown. Para código (Python, OpenSCAD, C++, etc.), usa bloques de código con el nombre del lenguaje."}
    
    # Construir el payload con imagen
    content_blocks = [{"type": "text", "text": user_prompt_text}]
    
    if image_file:
        image_b64 = encode_image_to_base64(image_file)
        mime_type = image_file.mimetype or "image/jpeg"
        
        content_blocks.append({
            "type": "image_url",
            "image_url": {
                "url": f"data:{mime_type};base64,{image_b64}",
                "detail": "high"
            }
        })
    
    # Construir mensajes para la API
    api_messages = [sys_msg] + [
        {"role": msg["role"], "content": msg["content"]} 
        for msg in messages
    ]
    
    # Agregar el mensaje actual con imagen
    api_messages.append({"role": "user", "content": content_blocks})
    
    payload = {
        "model": model,
        "messages": api_messages,
        "temperature": 0.3,
        "max_tokens": 8192,
        "top_p": 1
    }
    
    try:
        r = requests.post(url, headers=headers, json=payload, timeout=60)
        if r.status_code != 200:
            raise Exception(f"Groq API Error ({r.status_code}): {r.text}")
        
        response_data = r.json()
        return response_data["choices"][0]["message"]["content"]
        
    except Exception as e:
        logging.error(f"Error en Groq Vision: {str(e)}")
        raise Exception(f"Error en Groq Vision API: {str(e)}")

# --- CLIENTE DE API 4: DEEPSEEK (GRATUITO) ---
def call_deepseek(messages, model, key, user_prompt_text, image_file=None):
    """Llama a DeepSeek API gratuita"""
    url = "https://api.deepseek.com/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json"
    }
    
    # Mensaje del sistema
    sys_msg = {"role": "system", "content": "Responde siempre usando Markdown. Para código (Python, OpenSCAD, C++, etc.), usa bloques de código con el nombre del lenguaje."}
    
    # Construir mensajes para la API
    api_messages = [sys_msg] + [
        {"role": msg["role"], "content": msg["content"]} 
        for msg in messages
    ]
    
    # Agregar el mensaje actual
    api_messages.append({"role": "user", "content": user_prompt_text})
    
    payload = {
        "model": model,
        "messages": api_messages,
        "temperature": 0.3,
        "max_tokens": 8192,
        "stream": False
    }
    
    # Si hay imagen, usar el endpoint de visión
    if image_file and model == "deepseek-vision":
        vision_url = "https://api.deepseek.com/v1/chat/completions"
        
        # Construir contenido multimodal
        content_blocks = [{"type": "text", "text": user_prompt_text}]
        
        image_b64 = encode_image_to_base64(image_file)
        mime_type = image_file.mimetype or "image/jpeg"
        
        content_blocks.append({
            "type": "image_url",
            "image_url": f"data:{mime_type};base64,{image_b64}"
        })
        
        # Reemplazar el último mensaje con contenido multimodal
        api_messages[-1] = {"role": "user", "content": content_blocks}
        
        payload["messages"] = api_messages
        
        try:
            r = requests.post(vision_url, headers=headers, json=payload, timeout=60)
            if r.status_code != 200:
                raise Exception(f"DeepSeek Vision API Error ({r.status_code}): {r.text}")
            
            response_data = r.json()
            return response_data["choices"][0]["message"]["content"]
            
        except Exception as e:
            logging.error(f"Error en DeepSeek Vision: {str(e)}")
            raise Exception(f"Error en DeepSeek Vision API: {str(e)}")
    
    else:
        # Llamada normal de texto
        try:
            r = requests.post(url, headers=headers, json=payload, timeout=60)
            if r.status_code != 200:
                raise Exception(f"DeepSeek API Error ({r.status_code}): {r.text}")
            
            response_data = r.json()
            return response_data["choices"][0]["message"]["content"]
            
        except Exception as e:
            logging.error(f"Error en DeepSeek: {str(e)}")
            raise Exception(f"Error en DeepSeek API: {str(e)}")

# --- MODELOS DISPONIBLES (v4.7.1 - Dinámico) ---

def get_default_groq_models():
    """Devuelve una lista estática de Groq models como respaldo."""
    return {
        "groq_vision_models": [
            {"id": "meta-llama/llama-4-scout-17b-16e-instruct", "name": "Llama 4 Scout 17B", "emoji": "🦙", "vision": True, "provider": "groq"},
            {"id": "meta-llama/llama-4-maverick-17b-128e-instruct", "name": "Llama 4 Maverick 17B", "emoji": "🦙", "vision": True, "provider": "groq"}
        ],
        "groq_text_models": [
            {"id": "llama-3.3-70b-versatile", "name": "Llama 3.3 70B", "emoji": "🦙", "vision": False, "provider": "groq"},
            {"id": "llama-3.1-8b-instant", "name": "Llama 3.1 8B", "emoji": "🦙", "vision": False, "provider": "groq"},
            {"id": "mixtral-8x7b-32768", "name": "Mixtral 8x7B", "emoji": "🌀", "vision": False, "provider": "groq"},
            {"id": "gemma2-9b-it", "name": "Gemma2 9B", "emoji": "💎", "vision": False, "provider": "groq"},
            {"id": "qwen-qwq-32b", "name": "Qwen QWQ 32B", "emoji": "📐", "vision": False, "provider": "groq"},
            {"id": "openai/gpt-oss-120b", "name": "GPT-OSS 120B", "emoji": "🌎", "vision": False, "provider": "groq"},
            {"id": "openai/gpt-oss-20b", "name": "GPT-OSS 20B", "emoji": "🌎", "vision": False, "provider": "groq"},
            {"id": "meta-llama/llama-guard-4-12b", "name": "Llama Guard 4 12B", "emoji": "🛡️", "vision": False, "provider": "groq"}
        ]
    }

def fetch_live_groq_models(key):
    """Intenta obtener la lista de modelos en vivo desde Groq."""
    try:
        url = "https://api.groq.com/openai/v1/models"
        headers = {"Authorization": f"Bearer {key}"}
        r = requests.get(url, headers=headers, timeout=5)
        if r.status_code != 200:
            return None # API call failed, use fallback

        data = r.json().get("data", [])
        vision_models = []
        text_models = []
        
        for model in data:
            model_id = model.get("id")
            if not model_id:
                continue
            
            is_vision = model.get("capabilities", {}).get("vision", False)
            
            emoji = "🦙" # Default Llama
            if "gemma" in model_id: emoji = "💎"
            if "mixtral" in model_id: emoji = "🌀"
            if "qwen" in model_id: emoji = "📐"
            if "gpt-oss" in model_id: emoji = "🌎"
            if "guard" in model_id: emoji = "🛡️"

            name = model_id.split('/')[-1].replace('-', ' ').title()
            name = re.sub(r'\bIt\b', 'IT', name)
            name = re.sub(r'\bOss\b', 'OSS', name)
            
            m_data = {
                "id": model_id,
                "name": name,
                "emoji": emoji,
                "vision": is_vision,
                "provider": "groq"
            }
            
            if is_vision:
                vision_models.append(m_data)
            else:
                text_models.append(m_data)
        
        if not text_models and not vision_models:
            return None # Empty list, use fallback
            
        return {"groq_vision_models": vision_models, "groq_text_models": text_models}
    
    except Exception as e:
        print(f"⚠️ Error fetching live Groq models: {e}. Using static list.")
        return None # Any error, use fallback

def get_available_models():
    """Devuelve la lista de modelos disponibles"""
    deepseek_cfg = load_deepseek_config()
    deepseek_enabled = bool(deepseek_cfg.get("apiKey"))
    groq_cfg = load_groq_config()
    groq_key = groq_cfg.get("apiKey")
    
    models = {
        "gemini_models": [
            {"id": "gemini-2.5-pro", "name": "Gemini 2.5 Pro", "emoji": "🤖", "vision": True, "provider": "google"},
            {"id": "gemini-2.0-flash", "name": "Gemini 2.0 Flash", "emoji": "⚡", "vision": True, "provider": "google"},
            {"id": "gemini-1.5-flash", "name": "Gemini 1.5 Flash", "emoji": "⚡", "vision": True, "provider": "google"},
            {"id": "gemini-1.5-pro", "name": "Gemini 1.5 Pro", "emoji": "🤖", "vision": True, "provider": "google"}
        ]
    }
    
    # Try to get live Groq models, otherwise use static fallback
    groq_models = None
    if groq_key:
        groq_models = fetch_live_groq_models(groq_key)
    
    if not groq_models:
        groq_models = get_default_groq_models()
    
    models.update(groq_models)
    
    # Agregar modelos DeepSeek si está habilitado
    if deepseek_enabled:
        models["deepseek_models"] = [
            {"id": "deepseek-chat", "name": "DeepSeek V2", "emoji": "🔍", "vision": False, "provider": "deepseek"},
            {"id": "deepseek-coder", "name": "DeepSeek Coder", "emoji": "💻", "vision": False, "provider": "deepseek"},
            {"id": "deepseek-vision", "name": "DeepSeek Vision", "emoji": "👁️", "vision": True, "provider": "deepseek"}
        ]
    
    return models

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
        model = d.get("model") or "gemini-2.5-pro"
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
        
        elif model_id.startswith("deepseek-"):
            cfg = load_deepseek_config()
            api_key = cfg.get("apiKey")
            if not api_key: return jsonify({"error": "Falta API Key de DeepSeek"}), 403
            reply = call_deepseek(api_msgs[:-1], model_id, api_key, user_prompt_text=content, image_file=None)
        
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
    content = request.form.get("content", "")
    file = request.files.get("file")
    
    if not file:
        return jsonify({"error": "No se recibió ningún archivo de imagen."}), 400
    
    # --- Guardar mensaje con nombre de archivo ---
    c["messages"].append({"role": "user", "content": content, "ts": time.time(), "attachment": file.filename})
    with open(os.path.join(CHATS_DIR, cid, "messages.json"), "w") as f:
        json.dump(c["messages"], f)
    
    try:
        api_msgs = [{"role": m["role"], "content": m["content"]} for m in c["messages"]]
        
        # DETERMINAR QUÉ API USAR SEGÚN EL MODELO
        if model_id.startswith("gemini-"):
            # Usar Gemini para modelos Gemini
            cfg = load_gemini_config()
            api_key = cfg.get("apiKey")
            if not api_key:
                return jsonify({"error": "Falta API Key de Gemini"}), 403
            reply = call_gemini(api_msgs[:-1], model_id, api_key, user_prompt_text=content, image_file=file)
            
        elif model_id == "deepseek-vision":
            # Usar DeepSeek Vision
            cfg = load_deepseek_config()
            api_key = cfg.get("apiKey")
            if not api_key:
                return jsonify({"error": "Falta API Key de DeepSeek"}), 403
            reply = call_deepseek(api_msgs[:-1], model_id, api_key, user_prompt_text=content, image_file=file)
            
        else:
            # Usar Groq Vision
            cfg = load_groq_config()
            api_key = cfg.get("apiKey")
            if not api_key:
                return jsonify({"error": "Falta API Key de Groq"}), 403
            
            reply = call_groq_vision(api_msgs[:-1], model_id, api_key, user_prompt_text=content, image_file=file)
            
        # Guardar respuesta
        c["messages"].append({"role": "assistant", "content": reply, "ts": time.time()})
        with open(os.path.join(CHATS_DIR, cid, "messages.json"), "w") as f:
            json.dump(c["messages"], f)
        c["meta"]["updated_at"] = time.time()
        with open(os.path.join(CHATS_DIR, cid, "metadata.json"), "w") as f:
            json.dump(c["meta"], f)
        
        return jsonify({"reply": reply})

    except Exception as e:
        logging.exception("Error en r_message_vision")
        error_msg = str(e)
        
        # Proporcionar mensajes de error más útiles
        if "model_decommissioned" in error_msg:
            error_msg = "El modelo seleccionado ha sido descontinuado. Por favor, selecciona otro modelo."
        elif "model_not_found" in error_msg or "models/" in error_msg:
            error_msg = f"Modelo no encontrado: {model_id}. Verifica que el nombre del modelo sea correcto."
            
        return jsonify({"error": error_msg}), 500

# Nueva ruta para obtener modelos disponibles
@app.route('/api/available_models')
@basic_auth.required
def r_available_models():
    """Devuelve la lista de modelos disponibles"""
    models = get_available_models()
    return jsonify(models)

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
    if "deepseekApiKey" in d:
        cfg_ds = load_deepseek_config(); cfg_ds["apiKey"] = d["deepseekApiKey"]
        with open(DEEPSEEK_CONFIG, "w") as f: json.dump(cfg_ds, f)
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
@basic_auth.required
def r_download_stl(filename):
    @after_this_request
    def cleanup(response):
        try: os.remove(os.path.join(STL_DIR, filename))
        except: pass
        return response
    return send_from_directory(STL_DIR, filename, as_attachment=True)

@app.route('/')
@basic_auth.required
def index(): return render_template("index.html")

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    print(f"\n✅ Servidor v4.7.1 con Groq Dinámico iniciado en: http://{get_local_ip()}:5000")
    print("🎯 Nuevas características:")
    print("   - 🔄 ¡Botón 'Modelos' ahora es dinámico! Llama a la API de Groq.")
    print("   - 🖼️ Botón 'Enviar Imagen' abre selector completo (Cámara/Galería).")
    print("   - 🔍 DeepSeek API gratuita integrada.")
    app.run(host='0.0.0.0', port=5000, threaded=True)
EOF

# 7. Escribir frontend (index.html) v4.7.1
echo -e "${BLUE}📝 Escribiendo interfaz (index.html) v4.7.1...${NC}"
cat > ~/ia-workstation/templates/index.html <<'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>IA Workstation v4.7.1</title>

<meta name="theme-color" content="#4CAF50"/>
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="IA-WS">
<link rel="manifest" href="/static/manifest.json">

<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css">
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>

<style>
:root { --bg: #1e1e1e; --card: #2d2d2d; --text: #e0e0e0; --acc: #4CAF50; --blue: #2196F3; --deepseek: #00B894; }
body { background: var(--bg); color: var(--text); font-family: sans-serif; margin:0; padding:10px; }
.box { background: var(--card); padding: 15px; border-radius: 12px; margin-bottom: 15px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
h1, h3 { margin: 0 0 10px 0; color: var(--acc); }
button { padding: 8px 12px; border-radius: 6px; border: none; cursor: pointer; font-weight: bold; margin: 0 5px 5px 0; }
.btn-p { background: var(--acc); color: white; }
.btn-s { background: #555; color: white; }
.btn-gh { background: #333; color: white; }
.btn-gemini { background: #4285F4; color: white; }
.btn-vision { background: #8E44AD; color: white; }
.btn-deepseek { background: var(--deepseek); color: white; }
input[type="text"], select { 
    width: 100%; padding: 10px; box-sizing: border-box; 
    border-radius: 6px; border: 1px solid #444; 
    background: #333; color: white; 
}
select { 
    margin-top: 10px; 
    font-size: 0.85em !important;
    padding: 8px !important;
}
#hw { font-size:0.8em; color:#aaa; min-height: 1em; }
#messages { height: 50vh; overflow-y: auto; padding: 10px; border: 1px solid #444; border-radius: 8px; margin-bottom: 10px; background: #252526; }
.msg { padding: 10px; margin: 8px 0; border-radius: 8px; max-width: 95%; word-wrap: break-word; }
.msg.user { background: #3a3a3a; margin-left: auto; border-right: 3px solid var(--acc); }
.msg.assistant { background: #2d2d30; margin-right: auto; border-left: 3px solid var(--blue); }
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
.chat-row { display: flex; justify-content: space-between; padding: 8px; background: #333; margin-bottom: 4px; border-radius: 4px; }
.chat-row span { cursor: pointer; }

/* --- NUEVO v4.6 --- */
.attachment-note { color: #ccc; font-style: italic; font-size: 0.9em; margin-top: 5px; }
.msg-thumbnail { max-width: 120px; max-height: 120px; border-radius: 5px; margin-top: 5px; cursor: pointer; }
.preview-thumbnail { max-width: 50px; max-height: 50px; border-radius: 5px; vertical-align: middle; margin-right: 5px; }
.cancel-btn { background: #f44336; color: white; padding: 2px 6px; font-size: 0.8em; margin-left: 5px; }
.model-info { font-size: 0.75em; color: #888; margin-top: 5px; text-align: center; }
.vision-badge { background: #8E44AD; color: white; padding: 2px 6px; border-radius: 10px; font-size: 0.7em; margin-left: 5px; }
.free-badge { background: var(--deepseek); color: white; padding: 2px 6px; border-radius: 10px; font-size: 0.7em; margin-left: 5px; }
.refresh-btn { background: #FF9800; color: white; }
/* --- FIN NUEVO --- */
</style>
</head>
<body>

<div class="box">
    <h1>🧠 IA Workstation v4.7.1</h1>
    <div id="hw">Cargando hardware...</div>
    <div style="margin-top:10px;">
        <button class="btn-p" onclick="newChat()">➕ Nuevo</button>
        <button class="btn-s" onclick="askKey('groq')">🔐 Groq Key</button>
        <button class="btn-gemini" onclick="askKey('gemini')">🤖 Gemini Key</button>
        <button class="btn-deepseek" onclick="askKey('deepseek')">🔍 DeepSeek Key</button>
        <button class="btn-gh" onclick="askKey('github')">☁️ GitHub Token</button>
        <button class="btn-s" onclick="document.getElementById('fileInputOcr').click()">📎 OCR PDF/IMG</button>
        <button class="btn-vision" onclick="document.getElementById('fileInputVision').click()">📷 Enviar Imagen</button>
        <button class="refresh-btn" onclick="refreshModels()" title="Actualizar lista de modelos (obtiene lista en vivo de Groq)">🔄 Modelos</button>
    </div>
    <input type="file" id="fileInputOcr" hidden onchange="uploadOcrFile()" accept=".pdf,.jpg,.png,.txt">
    <input type="file" id="fileInputVision" hidden onchange="prepareVisionFile()" accept=".jpg,.jpeg,.png,.webp,.gif">
    
    <div id="uploadPreview" style="font-size:0.8em; color:var(--acc); margin-top:10px;"></div>
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
            </select>
        <div id="modelInfo" class="model-info">
            💡 <span class="vision-badge">VISIÓN</span> = Imágenes | 
            <span class="free-badge">GRATIS</span> = DeepSeek
        </div>
    </div>
</div>

<div class="box">
    <h3>Historial</h3>
    <div id="chatList">Cargando chats...</div>
</div>

<script>
let currChat = null;
let ocrText = "";
let pendingImageFile = null;
let pendingImageURL = null;
let githubReady = false;
let deepseekEnabled = false;

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
        const language = hljs.getLanguage(lang) ? lang : 'plaintext';
        return hljs.highlight(code, { language }).value;
    }
});

async function init() {
    api('/info').then(hw => {
        $('hw').textContent = `${hw.ram} | ${hw.battery} | ${hw.disk} | IP: ${hw.local_ip}`;
        githubReady = hw.github_enabled;
        deepseekEnabled = hw.deepseek_enabled;
    }).catch(e => {
        $('hw').textContent = `⚠️ Error hardware (no crítico)`;
    });
    loadChats();
    refreshModels(); // Carga modelos al inicio
}

async function refreshModels() {
    const refreshBtn = document.querySelector('.refresh-btn');
    const originalText = refreshBtn.textContent;
    try {
        refreshBtn.textContent = '⏳ Cargando...';
        refreshBtn.disabled = true;

        const models = await api('/available_models'); // Llama al backend (que llama a Groq)
        updateModelSelector(models);
        
        refreshBtn.textContent = '✅ Actualizado';
        setTimeout(() => {
            refreshBtn.textContent = originalText;
            refreshBtn.disabled = false;
        }, 2000);
        
    } catch (e) {
        console.log('Error cargando modelos:', e.message);
        refreshBtn.textContent = '❌ Error';
        refreshBtn.style.background = '#f44336';
        setTimeout(() => {
            refreshBtn.textContent = '🔄 Modelos';
            refreshBtn.style.background = '';
            refreshBtn.disabled = false;
        }, 2000);
        
        // Cargar modelos de respaldo por si falla la API
        updateModelSelector({
            gemini_models: [
                {id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", emoji: "🤖", vision: true},
                {id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", emoji: "⚡", vision: true}
            ],
            groq_vision_models: [
                {id: "meta-llama/llama-4-scout-17b-16e-instruct", name: "Llama 4 Scout 17B", emoji: "🦙", vision: true}
            ],
            groq_text_models: [
                {id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B", emoji: "🦙", vision: false},
                {id: "mixtral-8x7b-32768", name: "Mixtral 8x7B", emoji: "🌀", vision: false},
                {id: "gemma2-9b-it", name: "Gemma2 9B", emoji: "💎", vision: false},
                {id: "qwen-qwq-32b", name: "Qwen QWQ 32B", emoji: "📐", vision: false}
            ],
            deepseek_models: [
                {id: "deepseek-chat", name: "DeepSeek V2", emoji: "🔍", vision: false},
                {id: "deepseek-vision", name: "DeepSeek Vision", emoji: "👁️", vision: true}
            ]
        });
    }
}

function updateModelSelector(models) {
    const select = $('modelSelect');
    const currentValue = select.value;
    
    select.innerHTML = '';
    
    // Helper para añadir grupos de opciones
    const addOptGroup = (label, modelList) => {
        if (!modelList || modelList.length === 0) return;
        
        const optgroup = document.createElement('optgroup');
        optgroup.label = label;
        
        modelList.forEach(model => {
            const option = document.createElement('option');
            option.value = model.id;
            let text = `${model.emoji} ${model.name}`;
            if (model.provider === 'deepseek') {
                 if (model.vision) text += ' 👁️';
                 text += ' 🆓';
            }
            if (model.provider === 'google' && model.vision) text += ' 👁️';
            
            option.textContent = text;
            optgroup.appendChild(option);
        });
        select.appendChild(optgroup);
    };

    // Agregar modelos en orden
    addOptGroup("🔍 DeepSeek (Gratuito)", models.deepseek_models);
    addOptGroup("🤖 Google Gemini", models.gemini_models);
    addOptGroup("🦙 Groq (Visión)", models.groq_vision_models);
    addOptGroup("🦙 Groq (Texto)", models.groq_text_models);
    
    // Restaurar valor seleccionado si existe, sino usar DeepSeek primero
    if (currentValue && Array.from(select.options).some(opt => opt.value === currentValue)) {
        select.value = currentValue;
    } else {
        const deepseekChat = select.querySelector('option[value="deepseek-chat"]');
        if (deepseekChat) {
            select.value = "deepseek-chat";
        } else if (select.options.length > 0) {
            select.value = select.options[0].value;
        }
    }
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
        c.messages.forEach(m => appendMsg(m));
        $('mainUI').style.display = 'block';
        $('ghUploadBtn').style.display = githubReady ? 'block' : 'none';
        
        // Asegurarse de que el modelo del chat esté seleccionado
        const modelExists = Array.from($('modelSelect').options).some(opt => opt.value === c.meta.model);
        if (modelExists) {
            $('modelSelect').value = c.meta.model;
        } else {
            // Si el modelo guardado no está en la lista (p.ej. Groq lo quitó)
            // se selecciona el primero de la lista.
            if ($('modelSelect').options.length > 0) {
                 $('modelSelect').value = $('modelSelect').options[0].value;
                 changeModel(); // Actualizar el modelo en el backend
            }
        }
        
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

function appendMsg(msg) {
    const d = document.createElement('div');
    const role = msg.role;
    const text = msg.content;
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
    } else {
        d.textContent = text;
        if (msg._local_url) {
            d.innerHTML += `<br><a href="${msg._local_url}" target="_blank" rel="noopener noreferrer"><img src="${msg._local_url}" class="msg-thumbnail" alt="Imagen adjunta"></a>`;
        } 
        else if (msg.attachment) {
            d.innerHTML += `<div class="attachment-note">📎 ${msg.attachment}</div>`;
        }
    }
    $('messages').appendChild(d);
    d.scrollIntoView();
}

async function send() {
    const txt = $('uIn').value.trim();
    if((!txt && !ocrText && !pendingImageFile) || !currChat) return;
    
    const finalTxt = ocrText ? (txt + "\n\n[Contexto Archivo]:\n" + ocrText) : txt;
    ocrText = ""; 
    $('uploadPreview').innerHTML = "";
    $('uIn').value = '';
    
    appendMsg({
        role: 'user', 
        content: finalTxt, 
        attachment: pendingImageFile ? pendingImageFile.name : null,
        _local_url: pendingImageURL
    });
    
    const thinking = document.createElement('div');
    thinking.className = 'msg assistant'; thinking.textContent = '...';
    $('messages').appendChild(thinking);

    try {
        let r;
        if (pendingImageFile) {
            const currentModel = $('modelSelect').value;
            // Verificar si el modelo es de visión
            const selectedOption = $('modelSelect').options[$('modelSelect').selectedIndex];
            const optionText = selectedOption ? selectedOption.textContent : "";
            const isVisionModel = optionText.includes('👁️') || currentModel.includes('vision') || currentModel.includes('gemini') || currentModel.includes('llama-4');
            
            if (!isVisionModel) {
                throw new Error("Este modelo no soporta imágenes. Usa un modelo con el ícono 👁️.");
            }
            
            const fd = new FormData();
            fd.append('content', finalTxt);
            fd.append('file', pendingImageFile);
            
            const res = await fetch(`/api/chats/${currChat}/message_vision`, {
                method: 'POST',
                body: fd
            });
            
            if (!res.ok) {
                const errText = await res.text();
                throw new Error(errText);
            }
            r = await res.json();
            
        } else {
            r = await api(`/chats/${currChat}/message`, 'POST', {content: finalTxt});
        }
        
        $('messages').removeChild(thinking);
        
        if (r.error) {
            throw new Error(r.error);
        }
        appendMsg({role: 'assistant', content: r.reply});

    } catch(e) {
        let errMsg = e.message;
        try {
            const errJson = JSON.parse(e.message);
            errMsg = errJson.error || e.message;
        } catch(e2) {}
        thinking.textContent = `Error: ${errMsg}`;
    } finally {
        if (pendingImageURL) URL.revokeObjectURL(pendingImageURL);
        pendingImageFile = null;
        pendingImageURL = null;
    }
}

function prepareVisionFile() {
    const file = $('fileInputVision').files[0];
    if (!file) return;
    
    // Simplificado, ya que el 'accept' del input filtra
    
    cancelAttachment(false);
    ocrText = "";

    pendingImageFile = file;
    pendingImageURL = URL.createObjectURL(file);
    
    $('uploadPreview').innerHTML = `
        <span>
            <img src="${pendingImageURL}" class="preview-thumbnail" alt="Preview">
            📷 ${file.name}
            <button class="cancel-btn" onclick="cancelAttachment(true)">❌</button>
        </span>`;
}

async function uploadOcrFile() {
    const f = $('fileInputOcr').files[0];
    if(!f) return;
    
    cancelAttachment(false);
    
    $('uploadPreview').textContent = "⏳ Procesando OCR... espera...";
    
    const fd = new FormData(); fd.append('file', f);
    try {
        const r = await fetch('/api/upload', {method:'POST', body:fd});
        const d = await r.json();
        if(d.text) {
            ocrText = d.text;
            $('uploadPreview').innerHTML = `
                <span>
                    ✅ Texto OCR capturado.
                    <button class="cancel-btn" onclick="cancelAttachment(true)">❌</button>
                </span>`;
        } else { 
            $('uploadPreview').textContent = `❌ Error OCR: ${d.error || ''}`; 
        }
    } catch(e) { alert(e); }
    $('fileInputOcr').value = '';
}

function cancelAttachment(clearInputs = true) {
    if (pendingImageURL) {
        URL.revokeObjectURL(pendingImageURL);
        pendingImageURL = null;
    }
    pendingImageFile = null;
    ocrText = "";
    $('uploadPreview').innerHTML = '';
    
    if(clearInputs) {
        $('fileInputOcr').value = '';
        $('fileInputVision').value = '';
    }
}

async function askKey(type) {
    let payload = {};
    let message = "";
    
    if(type === 'groq') {
        const k = prompt("Groq API Key (gsk_...):");
        if(k) payload = {groqApiKey: k};
        else return;
        message = "Groq";
    } else if (type === 'gemini') {
        const k = prompt("Google AI Studio API Key:");
        if(k) payload = {geminiApiKey: k};
        else return;
        message = "Gemini";
    } else if (type === 'deepseek') {
        const k = prompt("DeepSeek API Key (gratuita - obténla en platform.deepseek.com):");
        if(k) payload = {deepseekApiKey: k};
        else return;
        message = "DeepSeek";
    } else if (type === 'github') {
        const k = prompt("GitHub Token (ghp_...):");
        if(k && k.startsWith('ghp_')) {
            payload = {githubToken: k};
        } else if (k) { alert("Token inválido. Debe empezar con ghp_"); return; }
        else return;
        message = "GitHub";
    }
    
    try {
        await api('/config', 'POST', payload);
        if (type === 'github') {
             githubReady = true;
             alert("Token guardado. El botón de subida se activará en los chats.");
        } else {
             alert(`${message} API Key guardada.`);
             // Actualizar modelos después de agregar una API key
             refreshModels();
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

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/static/sw.js')
    .then(() => console.log('Service Worker Registrado'))
    .catch(err => console.log('Error Service Worker: ', err));
}
</script>
</body>
</html>
EOF

# 8. Escribir el Service Worker (sw.js)
echo -e "${BLUE}📝 Escribiendo Service Worker (sw.js)...${NC}"
cat > ~/ia-workstation/static/sw.js <<'EOF'
const CACHE_NAME = 'ia-workstation-v4.7.1';
const FILES_TO_CACHE = [
  '/'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('Cacheando archivos de la app');
      return cache.addAll(FILES_TO_CACHE);
    })
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keyList) => {
      return Promise.all(keyList.map((key) => {
        if (key !== CACHE_NAME) {
          return caches.delete(key);
        }
      }));
    })
  );
});

self.addEventListener('fetch', (e) => {
  if (e.request.url.includes('/api/')) {
    e.respondWith(fetch(e.request));
    return;
  }
  e.respondWith(
    caches.match(e.request).then((response) => {
      return response || fetch(e.request);
    })
  );
});
EOF

# 9. Escribir el Manifest (manifest.json)
echo -e "${BLUE}📝 Escribiendo Manifest (manifest.json)...${NC}"
cat > ~/ia-workstation/static/manifest.json <<'EOF'
{
  "name": "IA Workstation",
  "short_name": "IA-WS",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#1e1e1e",
  "theme_color": "#4CAF50",
  "description": "Servidor local de IA para Termux.",
  "icons": [
    {
      "src": "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iI0RDRENEQyI+PHBhdGggZD0iTTEyIDJDNi40OCA MiAyIDYuNDggMiAxMnM0LjQ4IDEwIDEwIDEwIDEwLTQuNDggMTAtMTBTMTcuNTIgMiAxMiAyem0zLjUgMTJjMCAuMjgtLjAyLjU1LS4wNi44MkwxMS41IDIxLjE3Yy0uMTcuMjItLjQyLjM2LS43LjM2cy0uNTMtLjE0LS43LS4zNmwtMy45NS04LjMzYy0uMDQtLjI3LS4wNi0uNTQtLjA2LS44MiAwLTEuOTMgMS41Ny0zLjUgMy41LTMuNXMzLjUgMS41NyAzLjUgMy41em0yLjM5LTIuMzZDNS4xMyA5LjY0IDUuMTIgNy43OSA2LjI2IDYuMjZhMS41IDEuNSAwIDAgMSAxLjI5LS43NmMuMzEgMCAuNi4xLjg1LjI4bDEuNjEgMS4yOUM4LjM5IDguMTggNy4xOSA5LjY3IDcuMTkgMTEuNWMwIC4yOC4wMi41NS4wNi44MkwxMS41IDE4LjhjLjE3LjIyLjQyLjM2LjcuMzZzLjUzLS4xNC43LS4zNmwyLjM5LTUuMDNjLjA0LS4yNy4wNi0uNTQuMDYtLjgyIDAtMS44My0xLjE5LTMuMzItMi44MS00LjA3bDEuNjEtMS4yOWMuMjUtLjE5LjU0LS4yOC44NS0uMjhBMS41IDEuNSAwIDAgMSAxNy43NSA2LjI2YzEuMTMgMS41MyAxLjEyIDMuMzgtMS44NiA1ZTM4eiIvPjwvc3ZnPg==",
      "sizes": "192x192",
      "type": "image/svg+xml",
      "purpose": "any"
    },
    {
      "src": "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iI0RDRENEQyI+PHBhdGggZD0iTTEyIDJDNi40OCA MiAyIDYuNDggMiAxMnM0LjQ4IDEwIDEwIDEwIDEwLTQuNDggMTAtMTBTMTcuNTIgMiAxMiAyem0zLjUgMTJjMCAuMjgtLjAyLjU1LS4wNi44MkwxMS41IDIxLjE3Yy0uMTcuMjItLjQyLjM2LS43LjM2cy0uNTMtLjE0LS43LS4zNmwtMy45NS04LjMzYy0uMDQtLjI3LS4wNi0uNTQtLjA2LS44MiAwLTEuOTMgMS41Ny0zLjUgMy41LTMuNXMzLjUgMS41NyAzLjUgMy41em0yLjM5LTIuMzZDNS4xMyA5LjY0IDUuMTIgNy43OSA2LjI2IDYuMjZhMS41IDEuNSAwIDAgMSAxLjI5LS43NmMuMzEgMCAuNi4xLjg1LjI4bDEuNjEgMS4yOUM4LjM5IDguMTggNy4xOSA5LjY3IDcuMTkgMTEuNWMwIC4yOC4wMi41NS4wNi44MkwxMS41IDE4LjhjLjE3LjIyLjQyLjM2LjcuMzZzLjUzLS4xNC43LS4zNmwyLjM5LTUuMDNjLjA0LS4yNy4wNi0uNTQuMDYtLjgyIDAtMS44My0xLjE5LTMuMzItMi44MS00LjA3bDEuNjEtMS4yOWMuMjUtLjE5LjU0LS4yOC44NS0uMjhBMS41IDEuPSAwIDAgMSAxNy43NSA2LjI2YzEuMTMgMS41MyAxLjEyIDMuMzgtMS44NiA1ZTM4eiIvPjwvc3ZnPg==",
      "sizes": "512x512",
      "type": "image/svg+xml",
      "purpose": "any"
    }
  ]
}
EOF

# 10. Script de arranque (run.sh) usando VENV
echo -e "${BLUE}⚙️ Creando script de arranque (run.sh)...${NC}"
cat > ~/ia-workstation/run.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/ia-workstation
# Activar entorno virtual antes de ejecutar
source venv/bin/activate
echo "➡️ Iniciando Servidor v4.7.1 con Groq Dinámico..."
python app.py
EOF
chmod +x ~/ia-workstation/run.sh

# 11. Configuración inicial vacía
touch ~/ia-workstation/config/groq.json
touch ~/ia-workstation/config/github.json
touch ~/ia-workstation/config/gemini.json
touch ~/ia-workstation/config/deepseek.json

echo
echo -e "${GREEN}✅ INSTALACIÓN COMPLETADA CON ÉXITO v4.7.1${NC}"
echo
echo -e "🎯 NUEVAS CARACTERÍSTICAS:"
echo -e "  - 🔄 ¡Botón 'Modelos' ahora es dinámico! Llama a la API de Groq."
echo -e "  - 🖼️ Botón 'Enviar Imagen' abre selector completo (Cámara/Galería)."
echo -e "  - 🔍 DeepSeek API gratuita integrada."
echo
echo -e "Para iniciar, ejecuta:"
echo -e "${BLUE}  cd ~/ia-workstation && ./run.sh${NC}"
echo
