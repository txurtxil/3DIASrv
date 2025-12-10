#!/bin/bash
# ==========================================
# NEXUS WEBOS v31: TIME LORD
# ==========================================
# Fix: "Tiempo Desconocido" (Lectura Híbrida Log/Archivo)
# Core: Bambu A1 Mini + Gcode Nativo
# ==========================================

G='\033[0;32m'
C='\033[0;36m'
Y='\033[1;33m'
NC='\033[0m'

ANDROID_DOWNLOADS="/data/data/com.termux/files/home/storage/downloads"
IA3D_ROOT="$ANDROID_DOWNLOADS/ia3d"
TRIGGER_FILE="$IA3D_ROOT/.trigger_gui"

setup_environment() {
    if [ ! -d "$HOME/storage" ]; then termux-setup-storage; sleep 2; fi
    mkdir -p "$IA3D_ROOT"
    rm -f "$TRIGGER_FILE"

    if ! command -v termux-x11 &> /dev/null; then
        pkg update -y
        pkg install x11-repo tur-repo -y
        pkg install termux-x11-nightly proot-distro git python -y
    fi
    if [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" ]; then proot-distro install ubuntu; fi
}

inject_fusion_server() {
    echo -e "${C}[*] Actualizando Algoritmos de Tiempo...${NC}"
    
    proot-distro login ubuntu --bind "$IA3D_ROOT:/mnt/ia3d" --shared-tmp -- bash << 'EOF'
    export DEBIAN_FRONTEND=noninteractive
    
    apt update -q
    apt install -y python3 python3-pip python3-venv fluxbox prusa-slicer \
                   tesseract-ocr imagemagick poppler-utils openscad openscad-mcad git \
                   adwaita-icon-theme-full dbus-x11 procps curl ca-certificates mesa-utils grep
    
    mkdir -p /root/.fluxbox
    echo "session.screen0.toolbar.visible: false" > /root/.fluxbox/init

    # CONFIG PRUSA (PERFIL BAMBU CON FÍSICA)
    mkdir -p /root/.config/PrusaSlicer/printer
    cat > /root/.config/PrusaSlicer/printer/Bambu_A1_Mini_CLI.ini << 'INI'
[printer:Bambu_A1_Mini_CLI]
bed_shape = 0x0,180x0,180x180,0x180
gcode_flavor = marlin2
nozzle_diameter = 0.4
retract_length = 0.8
retract_speed = 30
use_relative_e_distances = 1
thumbnails = 96x96, 300x300
thumbnails_format = PNG
remaining_times = 1
# FÍSICA OBLIGATORIA PARA CÁLCULO DE TIEMPO
machine_max_acceleration_e = 5000
machine_max_acceleration_extruding = 10000
machine_max_acceleration_retracting = 5000
machine_max_acceleration_x = 10000
machine_max_acceleration_y = 10000
machine_max_acceleration_z = 500
machine_max_feedrate_e = 120
machine_max_feedrate_x = 500
machine_max_feedrate_y = 500
machine_max_feedrate_z = 12
machine_max_jerk_e = 2.5
machine_max_jerk_x = 10
machine_max_jerk_y = 10
machine_max_jerk_z = 0.2
perimeter_speed = 60
solid_infill_speed = 80
travel_speed = 300
first_layer_speed = 30
start_gcode = M104 S220\nM140 S60\nG28\nM190 S60\nM109 S220\nG1 Z10 F3000\nG1 X0 Y0 F3000\nG1 Z0.2 F300\nG1 X20 E10 F1000\n
end_gcode = M104 S0\nM140 S0\nG1 X0 Y180 F3000\nM84
INI

    mkdir -p /root/.config/PrusaSlicer
    echo "[App]\nview_mode = expert\nversion_check = 0\nshow_splash_screen = 0" > /root/.config/PrusaSlicer/PrusaSlicer.ini

    mkdir -p /opt/nexus /mnt/ia3d/{chats,config,stl_exports} templates static
    cd /opt/nexus
    if [ ! -d "venv" ]; then python3 -m venv venv; ./venv/bin/pip install flask flask-basicauth requests uuid python-dotenv certifi; fi

    # --- LAMINAR.SH ---
    cat > /opt/nexus/laminar.sh << 'SCRIPT'
#!/bin/bash
FILE_PATH="$1"
SPEED="$2"
OUTPUT="${FILE_PATH}.gcode"
CONFIG="/root/.config/PrusaSlicer/printer/Bambu_A1_Mini_CLI.ini"

FLAGS=""
if [ "$SPEED" == "slow" ]; then FLAGS="--perimeter-speed 40"; fi
if [ "$SPEED" == "fast" ]; then FLAGS="--perimeter-speed 120"; fi

# Ejecutar y forzar escritura en disco
prusa-slicer --load "$CONFIG" --export-gcode --output "$OUTPUT" --support-material --support-material-auto $FLAGS "$FILE_PATH" 2>&1
sync
SCRIPT
    chmod +x /opt/nexus/laminar.sh

    # --- GUI.SH ---
    cat > /opt/nexus/gui.sh << 'SCRIPT'
#!/bin/bash
export DISPLAY=$1
export GALLIUM_DRIVER=llvmpipe
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_GL_VERSION_OVERRIDE=3.3
export MESA_GLSL_VERSION_OVERRIDE=330
rm -rf /root/.config/PrusaSlicer/cache
fluxbox &
cd /mnt/ia3d/stl_exports
dbus-run-session prusa-slicer
pkill fluxbox
SCRIPT
    chmod +x /opt/nexus/gui.sh

    # --- APP.PY (TIME HUNTER MEJORADO) ---
    cat > app.py << 'PYTHON'
import os, json, uuid, time, requests, subprocess, certifi, traceback, shutil, re
from flask import Flask, request, jsonify, render_template

BASE_DIR = "/opt/nexus"
DATA_DIR = "/mnt/ia3d"
STL_DIR = os.path.join(DATA_DIR, "stl_exports")
TRIGGER_PATH = os.path.join(DATA_DIR, ".trigger_gui")
CHATS_DIR = os.path.join(DATA_DIR, "chats")
CONFIG_DIR = os.path.join(DATA_DIR, "config")
GROQ_CFG = os.path.join(CONFIG_DIR, "groq.json")
GEMINI_CFG = os.path.join(CONFIG_DIR, "gemini.json")

app = Flask(__name__)
app.config['SEND_FILE_MAX_AGE_DEFAULT'] = 0

@app.after_request
def add_header(response):
    response.headers['Cache-Control'] = 'no-store'
    return response

def load_key(p): return json.load(open(p)).get("apiKey") if os.path.exists(p) else ""

def call_llm(model, msgs, key):
    try:
        sys_prompt = "Role: OpenSCAD Expert. Rules: 1. Output ONLY valid OpenSCAD code. 2. Wrap code in ```openscad ... ```. 3. Use standard libraries."
        if "gemini" in model:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
            full_prompt = f"{sys_prompt}\n\nContext:\n"
            for m in msgs: full_prompt += f"{m['role'].upper()}: {m['content']}\n"
            r = requests.post(url, json={"contents": [{"parts": [{"text": full_prompt}]}]}, verify=certifi.where(), timeout=30)
            if r.status_code != 200: 
                if r.status_code == 429: return "❌ CUOTA EXCEDIDA (429)."
                return f"❌ Error Google ({r.status_code}): {r.text}"
            data = r.json()
            if "candidates" not in data: return f"❌ Bloqueo API: {json.dumps(data)}"
            return data["candidates"][0]["content"]["parts"][0]["text"]
        else:
            url = "https://api.groq.com/openai/v1/chat/completions"
            payload = {"model": model, "messages": [{"role":"system", "content":sys_prompt}] + msgs[-4:], "temperature": 0.1}
            r = requests.post(url, headers={"Authorization": f"Bearer {key}"}, json=payload, verify=certifi.where(), timeout=30)
            if r.status_code != 200: return f"❌ Error Groq ({r.status_code}): {r.text}"
            return r.json()["choices"][0]["message"]["content"]
    except Exception as e: return f"❌ Error Interno: {str(e)}"

@app.route('/')
def index(): return render_template("index.html")

@app.route('/api/chats', methods=['GET', 'POST'])
def chats():
    if request.method == 'POST':
        cid = str(uuid.uuid4())
        cdir = os.path.join(CHATS_DIR, cid)
        os.makedirs(cdir, exist_ok=True)
        json.dump({"title": request.json.get("title"), "model": request.json.get("model")}, open(os.path.join(cdir, "metadata.json"), "w"))
        json.dump([], open(os.path.join(cdir, "messages.json"), "w"))
        return jsonify({"chat_id": cid})
    res = []
    if os.path.exists(CHATS_DIR):
        for c in os.listdir(CHATS_DIR):
            try: res.append({**json.load(open(os.path.join(CHATS_DIR, c, "metadata.json"))), "chat_id": c})
            except: pass
    return jsonify(res)

@app.route('/api/chats/<cid>/message', methods=['POST'])
def message(cid):
    txt = request.json.get("content")
    cdir = os.path.join(CHATS_DIR, cid)
    msgs = json.load(open(os.path.join(cdir, "messages.json")))
    meta = json.load(open(os.path.join(cdir, "metadata.json")))
    msgs.append({"role": "user", "content": txt})
    key = load_key(GEMINI_CFG if "gemini" in meta["model"] else GROQ_CFG)
    reply = call_llm(meta["model"], msgs, key) if key else "⚠️ ERROR: No hay API Key."
    msgs.append({"role": "assistant", "content": reply})
    json.dump(msgs, open(os.path.join(cdir, "messages.json"), "w"))
    return jsonify({"reply": reply})

@app.route('/api/chats/<cid>', methods=['GET', 'DELETE'])
def chat_detail(cid):
    if request.method == 'DELETE':
        t = os.path.join(CHATS_DIR, cid)
        if os.path.exists(t): shutil.rmtree(t)
        return jsonify({"status": "deleted"})
    try: return jsonify({"meta": json.load(open(os.path.join(CHATS_DIR, cid, "metadata.json"))), "messages": json.load(open(os.path.join(CHATS_DIR, cid, "messages.json")))})
    except: return jsonify({"error": "404"}), 404

@app.route('/api/config', methods=['POST'])
def cfg():
    d = request.json
    if "groqApiKey" in d: json.dump({"apiKey": d["groqApiKey"]}, open(GROQ_CFG, "w"))
    if "geminiApiKey" in d: json.dump({"apiKey": d["geminiApiKey"]}, open(GEMINI_CFG, "w"))
    return jsonify({"status": "ok"})

@app.route('/api/compile_scad', methods=['POST'])
def compile():
    code = request.json.get("code")
    raw_name = request.json.get("filename", "IA_Object")
    safe_name = re.sub(r'[^a-zA-Z0-9_-]', '_', raw_name)
    scad = os.path.join(STL_DIR, f"{safe_name}.scad")
    stl = os.path.join(STL_DIR, f"{safe_name}.stl")
    try:
        with open(scad, "w") as f: f.write(code)
        env = os.environ.copy(); env["QT_QPA_PLATFORM"] = "offscreen"
        proc = subprocess.run(["openscad", "-o", stl, scad, "--colorscheme=Tomorrow"], env=env, capture_output=True, text=True)
        if proc.returncode != 0: return jsonify({"status": "error", "msg": proc.stderr})
        return jsonify({"status": "ok", "filename": f"{safe_name}.stl"})
    except Exception as e: return jsonify({"status": "error", "msg": str(e)})

@app.route('/api/launch_gui', methods=['POST'])
def gui():
    with open(TRIGGER_PATH, "w") as f: f.write("start")
    return jsonify({"status": "ok"})

@app.route('/api/slice_file', methods=['POST'])
def slice():
    f = request.json.get("filename")
    speed = request.json.get("speed", "normal")
    path = os.path.join(STL_DIR, f)
    gcode_path = f"{path}.gcode"
    
    if os.path.exists(gcode_path): os.remove(gcode_path)
    
    cmd = ["/bin/bash", "/opt/nexus/laminar.sh", path, speed]
    
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True)
        log_output = proc.stdout + proc.stderr
        
        # ESTRATEGIA 1: Buscar en el LOG de consola
        print_time = "Desconocido"
        match_log = re.search(r"Estimated printing time: (.*)", log_output)
        if match_log: 
            print_time = match_log.group(1).strip()
        else:
            # ESTRATEGIA 2: Si falla, buscar con GREP dentro del archivo
            if os.path.exists(gcode_path):
                try:
                    # Usamos grep para buscar la línea exacta, sin importar dónde esté
                    grep_out = subprocess.check_output(f"grep -i '; estimated printing time' '{gcode_path}' | tail -n 1", shell=True).decode()
                    if "=" in grep_out:
                        print_time = grep_out.split("=")[1].strip()
                except: pass

        if os.path.exists(gcode_path):
            return jsonify({"status": "ok", "msg": f"✅ G-Code Generado\n⏱️ Tiempo: {print_time}\n🚀 Perfil: {speed.upper()}"})
        else:
            return jsonify({"status": "error", "msg": f"Error CLI: {log_output[:500]}"})
            
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)})

@app.route('/api/files')
def files():
    f = []
    if os.path.exists(STL_DIR): f = [x for x in os.listdir(STL_DIR) if x.endswith(('.stl','.gcode'))]
    f.sort(key=lambda x: os.path.getmtime(os.path.join(STL_DIR, x)), reverse=True)
    return jsonify(f)

@app.route('/api/delete_file', methods=['POST'])
def delete_file():
    f = request.json.get("filename")
    path = os.path.join(STL_DIR, f)
    if os.path.exists(path):
        os.remove(path)
        if f.endswith(".stl"):
            if os.path.exists(path.replace(".stl", ".scad")): os.remove(path.replace(".stl", ".scad"))
            if os.path.exists(path + ".gcode"): os.remove(path + ".gcode")
        return jsonify({"status": "ok"})
    return jsonify({"status": "error"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYTHON

    # --- HTML ---
    cat > templates/index.html << 'HTML'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>NEXUS v31</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css">
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<style>
    body { background: #050505; color: #eee; font-family: monospace; padding: 10px; margin-bottom: 50px; }
    .box { border: 1px solid #333; padding: 10px; margin-bottom: 10px; border-radius: 5px; background: #111; }
    button { padding: 10px; width: 100%; margin-bottom: 5px; cursor: pointer; background: #333; color: white; border: 1px solid #555; border-radius: 4px; }
    .btn-green { background: #00e676; color: black; font-weight: bold; }
    .btn-blue { background: #2979ff; color: white; font-weight: bold; }
    .btn-red { background: #ff1744; color: white; }
    .btn-orange { background: #ff9100; color: black; font-weight: bold; }
    
    #messages { height: 40vh; overflow-y: auto; background: #000; border: 1px solid #333; padding: 10px; margin-bottom: 10px; }
    .msg { margin-bottom: 10px; padding: 8px; border-radius: 5px; position: relative; }
    .user { background: #222; text-align: right; }
    .assistant { background: #1a1a1a; border-left: 2px solid #00e676; padding-right: 30px; }
    
    .btn-copy { position: absolute; top: 2px; right: 2px; padding: 2px 5px; font-size: 0.7em; width: auto; background: #333; color: #aaa; border:none; }
    .btn-del { width: 30px; background: #ff1744; color: white; padding: 2px; margin-left: 5px; border:none; }
    
    input, select { width: 100%; padding: 10px; background: #222; color: white; border: 1px solid #444; box-sizing: border-box; margin-bottom: 5px; }
    optgroup { color: #00e676; background: #222; }
    
    .chat-item { display: flex; justify-content: space-between; align-items: center; padding: 8px; border-bottom: 1px solid #333; }
    
    .file-item { display: flex; justify-content: space-between; align-items: center; padding: 10px; background: #1a1a1a; margin-bottom: 5px; border-radius: 4px; border-left: 4px solid #555; }
    .file-item.stl { border-left-color: #2979ff; }
    .file-item.gcode { border-left-color: #00e676; }
    .file-name { font-size: 0.9em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 50%; }
    .file-actions { display: flex; gap: 5px; }
    .btn-mini { width: auto; padding: 5px 10px; font-size: 0.8em; margin: 0; }

    #editorModal, #sliceModal { display:none; position: fixed; top:0; left:0; width:100%; height:100%; background: rgba(0,0,0,0.9); z-index:100; }
    .modal-content { background:#111; margin: 5% auto; padding: 20px; width: 90%; height: 80%; border-radius: 8px; border: 1px solid #00e676; display: flex; flex-direction: column; }
    .small-modal { height: auto; margin: 20% auto; width: 80%; }
    
    #codeArea { flex: 1; background: #000; color: #0f0; border: 1px solid #333; padding: 10px; font-family: monospace; resize: none; }
    #errorLog { height: 60px; background: #220000; color: #ff5555; border: 1px solid #f00; padding: 5px; overflow-y: auto; font-size: 0.8em; margin-bottom: 10px; display: none; }
</style>
</head>
<body>

<div id="editorModal">
    <div class="modal-content">
        <h3 style="color:#00e676; margin:0 0 10px 0;">🛠️ EDITOR DE CÓDIGO</h3>
        <div id="errorLog"></div>
        <textarea id="codeArea"></textarea>
        <div style="display:flex; gap:10px; margin-top:10px;">
            <button class="btn-red" onclick="closeEditor()">CANCELAR</button>
            <button class="btn-green" onclick="retryCompile()">RECOMPILAR</button>
        </div>
    </div>
</div>

<div id="sliceModal">
    <div class="modal-content small-modal">
        <h3 style="color:#ff9100; margin:0 0 10px 0;">🎲 LAMINAR GCODE</h3>
        <label>Velocidad:</label>
        <select id="speedSelect">
            <option value="slow">🐢 Detallado</option>
            <option value="normal" selected>⚖️ Normal</option>
            <option value="fast">🚀 Rápido</option>
        </select>
        <div style="display:flex; gap:10px; margin-top:20px;">
            <button class="btn-red" onclick="$('sliceModal').style.display='none'">CANCELAR</button>
            <button class="btn-orange" onclick="confirmSlice()">EXPORTAR</button>
        </div>
    </div>
</div>

<button class="btn-green" onclick="launchGUI()">🖥️ ABRIR PRUSA SLICER (X11)</button>

<div class="box">
    <h3>📂 GESTOR DE ARCHIVOS</h3>
    <div id="files" style="max-height: 200px; overflow-y: auto;">Cargando...</div>
    <button onclick="loadFiles()">🔄 Refrescar Lista</button>
</div>

<div class="box">
    <div style="display:flex; gap:5px;">
        <button onclick="askKey('groq')">🔑 Groq</button>
        <button onclick="askKey('gemini')">🔑 Gemini</button>
    </div>
    <select id="model">
        <optgroup label="GOOGLE GEMINI (ELITE)">
            <option value="gemini-3-pro-preview">Gemini 3.0 Pro (Preview)</option>
            <option value="gemini-2.5-pro">Gemini 2.5 Pro</option>
            <option value="gemini-2.0-flash-exp">Gemini 2.0 Flash</option>
        </optgroup>
        <optgroup label="GROQ (LLAMA & OPENAI)">
            <option value="llama-3.3-70b-versatile">Llama 3.3 70B</option>
            <option value="meta-llama/llama-4-scout-17b-16e-instruct">Llama 4 Scout (17B)</option>
            <option value="openai/gpt-oss-120b">GPT-OSS 120B</option>
        </optgroup>
    </select>
    <div style="display:flex; justify-content:space-between; align-items:center;">
        <span>CHATS:</span>
        <button onclick="newC()" style="width:auto; padding:5px 10px;">+ Nuevo</button>
    </div>
    <div id="chats" style="max-height:150px; overflow-y:auto; margin-top:5px;"></div>
</div>

<div class="box">
    <div id="messages"></div>
    <div style="display:flex; gap:5px;">
        <input id="in" placeholder="Escribe..." onkeypress="if(event.key=='Enter') send()">
        <button onclick="send()" style="width:50px;">➤</button>
    </div>
</div>

<script>
let cid = null;
let currentStl = null;
const $ = id => document.getElementById(id);

function openEditor(code, errorMsg=null) {
    $('editorModal').style.display = 'block';
    $('codeArea').value = code;
    if(errorMsg) { $('errorLog').style.display='block'; $('errorLog').innerText=errorMsg; } 
    else $('errorLog').style.display='none';
}
function closeEditor() { $('editorModal').style.display = 'none'; }

function openSliceModal(f) {
    currentStl = f;
    $('sliceModal').style.display = 'block';
}

async function confirmSlice() {
    $('sliceModal').style.display = 'none';
    const speed = $('speedSelect').value;
    alert(`Laminando ${currentStl}...`);
    
    const d = await api('/api/slice_file', {
        method:'POST', 
        headers:{'Content-Type':'application/json'}, 
        body:JSON.stringify({filename: currentStl, speed: speed})
    });
    
    alert(d.msg);
    loadFiles();
}

async function api(url, opts={}) {
    try {
        const r = await fetch(url, opts);
        return await r.json();
    } catch(e) { return {error: e.message}; }
}

async function launchGUI() {
    await api('/api/launch_gui', {method:'POST'});
    alert("Iniciando X11... Abre Termux:X11");
}

async function loadFiles() {
    const f = await api('/api/files');
    $('files').innerHTML = f.map(x => {
        const type = x.endsWith('.gcode') ? 'gcode' : 'stl';
        const icon = type === 'gcode' ? '🖨️' : '🧊';
        
        const sliceBtn = type === 'stl' ? `<button class="btn-mini btn-blue" onclick="openSliceModal('${x}')">🔪</button>` : '';
        return `
        <div class="file-item ${type}">
            <span class="file-name">${icon} ${x}</span>
            <div class="file-actions">
                ${sliceBtn}
                <button class="btn-mini btn-red" onclick="delF('${x}')">🗑️</button>
            </div>
        </div>`;
    }).join('') || '<div style="text-align:center; color:#555">Carpeta vacía</div>';
}

async function delF(f) {
    if(!confirm(`¿Eliminar ${f}?`)) return;
    const d = await api('/api/delete_file', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({filename:f})});
    if(d.status === 'ok') loadFiles();
}

async function retryCompile() {
    const code = $('codeArea').value;
    const name = prompt("Nombre archivo:", "fixed");
    if(!name) return;
    const d = await api('/api/compile_scad', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({code, filename:name})});
    if(d.status=='ok') { alert(`✅ OK`); closeEditor(); loadFiles(); }
    else { $('errorLog').style.display='block'; $('errorLog').innerText=d.msg; }
}

async function comp(code) {
    const name = prompt("Nombre archivo:", "ia_part");
    if (!name) return;
    const d = await api('/api/compile_scad', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({code, filename:name})});
    if(d.status=='ok') { alert(`✅ OK`); loadFiles(); }
    else openEditor(code, "❌ ERROR:\n" + d.msg);
}

async function send() {
    const txt = $('in').value; if(!txt || !cid) return;
    $('in').value = '';
    appendMsg({role:'user', content:txt});
    const d = await api(`/api/chats/${cid}/message`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({content:txt})});
    if(d.reply) appendMsg({role:'assistant', content:d.reply});
    else appendMsg({role:'assistant', content:"Error: " + JSON.stringify(d)});
}

function appendMsg(m) {
    const d = document.createElement('div');
    d.className = `msg ${m.role}`;
    d.innerHTML = marked.parse(m.content);
    if(m.role === 'assistant') {
        const btn = document.createElement('button');
        btn.className = 'btn-copy'; btn.innerText = '📋';
        btn.onclick = () => { navigator.clipboard.writeText(m.content); alert("Copiado!"); };
        d.appendChild(btn);
    }
    if(m.content.includes('openscad')) {
        const code = m.content.split('```openscad')[1].split('```')[0];
        d.innerHTML += `<div style="display:flex; gap:5px; margin-top:5px;">
            <button onclick='comp(\`${code}\`)' class="btn-green">🛠️ GENERAR STL</button>
            <button onclick='openEditor(\`${code}\`)' class="btn-blue" style="width:auto;">👁️</button>
        </div>`;
    }
    $('messages').appendChild(d);
    $('messages').scrollTop = 99999;
}

async function newC() {
    const t = prompt("Nombre:"); if(!t) return;
    const model = $('model').value;
    const d = await api('/api/chats', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({title:t, model:model})});
    cid = d.chat_id; loadChats(); $('messages').innerHTML = '';
}

async function delC(e, id) {
    e.stopPropagation();
    if(confirm("¿Eliminar?")) { await api(`/api/chats/${id}`, {method:'DELETE'}); if(cid==id) {cid=null; $('messages').innerHTML='';} loadChats(); }
}

async function loadChats() {
    const d = await api('/api/chats');
    $('chats').innerHTML = d.map(c => `
        <div class="chat-item" onclick="load('${c.chat_id}')">
            <span class="chat-name" onclick="load('${c.chat_id}')">${c.title}</span>
            <button class="btn-del" onclick="delC(event, '${c.chat_id}')">X</button>
        </div>`).join('');
}

async function load(id) {
    cid = id;
    const d = await api(`/api/chats/${id}`);
    $('messages').innerHTML = '';
    d.messages.forEach(appendMsg);
}

async function askKey(t) {
    const k = prompt(`Key ${t}:`);
    if(k) api('/api/config', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({[t+'ApiKey']:k})});
}

loadChats();
loadFiles();
</script>
</body>
</html>
HTML
EOF
}

# ==========================================
# 3. EJECUCIÓN
# ==========================================

setup_environment
inject_fusion_server

echo -e "${G}╔════════════════════════════════════════════╗${NC}"
echo -e "${G}║   NEXUS v31: TIME LORD (HYBRID SEARCH)     ║${NC}"
echo -e "${G}╚════════════════════════════════════════════╝${NC}"
echo -e "${Y}>> Abre: http://localhost:5000${NC}"

# Iniciar Flask
proot-distro login ubuntu --bind "$IA3D_ROOT:/mnt/ia3d" --shared-tmp -- bash -c "
    cd /opt/nexus
    source venv/bin/activate
    python3 -u app.py
" &

# Watchdog para GUI
(
    while true; do
        if [ -f "$TRIGGER_FILE" ]; then
            rm -f "$TRIGGER_FILE"
            am force-stop com.termux.x11 >/dev/null 2>&1
            pkill -9 -f termux-x11
            rm -rf $PREFIX/tmp/.X11-unix; mkdir -p $PREFIX/tmp/.X11-unix; chmod 1777 $PREFIX/tmp/.X11-unix
            
            D=$((10 + RANDOM % 90))
            termux-x11 :$D -ac &
            while [ ! -S "$PREFIX/tmp/.X11-unix/X$D" ]; do sleep 0.1; done
            
            am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1
            
            proot-distro login ubuntu --bind "$IA3D_ROOT:/mnt/ia3d" --shared-tmp -- bash -c "/opt/nexus/gui.sh :$D" &
        fi
        sleep 1
    done
) &

wait
