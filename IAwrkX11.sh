#!/bin/bash
# ==========================================
# NEXUS WEBOS v45.1: FUTURE MODELS EDITION
# ==========================================
# Fecha Simulación: Diciembre 2025
# Core: Lista de archivos instantánea
# Modelos: Gemini 3.0, Gemini 2.5, OpenAI OSS 120B (Groq)
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
    echo -e "${C}[*] Actualizando Modelos (Dic 2025)...${NC}"
    
    proot-distro login ubuntu --bind "$IA3D_ROOT:/mnt/ia3d" --shared-tmp -- bash << 'EOF'
    export DEBIAN_FRONTEND=noninteractive
    
    apt update -q
    apt install -y python3 python3-pip python3-venv fluxbox prusa-slicer \
                   openscad git dbus-x11 procps curl ca-certificates mesa-utils grep sed
    
    mkdir -p /root/.fluxbox
    echo "session.screen0.toolbar.visible: false" > /root/.fluxbox/init
    
    # --- PRUSA SLICER CONFIG ---
    mkdir -p /root/.config/PrusaSlicer/printer
    cat > /root/.config/PrusaSlicer/printer/Bambu_Template.ini << 'INI'
[printer:Bambu_Template]
bed_shape = 0x0,180x0,180x180,0x180
gcode_flavor = marlin2
nozzle_diameter = 0.4
retract_length = 0.8
retract_speed = 30
use_relative_e_distances = 1
thumbnails = 0x0
machine_max_acceleration_e = 5000
machine_max_acceleration_x = 10000
machine_max_acceleration_y = 10000
machine_max_acceleration_z = 500
machine_max_feedrate_x = 500
machine_max_feedrate_y = 500
machine_max_feedrate_z = 12
perimeter_speed = 60
solid_infill_speed = 80
travel_speed = 300
first_layer_speed = 30
fill_density = 15%
fill_pattern = gyroid
support_material = 0
support_material_style = organic
support_material_auto = 0
start_gcode = M104 S__NOZZLE__\nM140 S__BED__\nG28\nM190 S__BED__\nM109 S__NOZZLE__\nG1 Z10 F3000\nG1 X0 Y0 F3000\nG1 Z0.2 F300\nG1 X20 E10 F1000\n
end_gcode = M104 S0\nM140 S0\nG1 X0 Y180 F3000\nM84
INI

    mkdir -p /root/.config/PrusaSlicer
    echo "[App]\nview_mode = expert\nversion_check = 0\nshow_splash_screen = 0" > /root/.config/PrusaSlicer/PrusaSlicer.ini

    mkdir -p /opt/nexus /mnt/ia3d/{chats,config,stl_exports} templates static
    cd /opt/nexus
    if [ ! -d "venv" ]; then python3 -m venv venv; ./venv/bin/pip install flask requests uuid python-dotenv certifi; fi

    # --- SCRIPTS AUXILIARES ---
    cat > /opt/nexus/laminar.sh << 'SCRIPT'
#!/bin/bash
FILE_PATH="$1"
SPEED="$2"
MAT="$3"
SUP="$4"
OUTPUT="${FILE_PATH}.gcode"
TEMPLATE="/root/.config/PrusaSlicer/printer/Bambu_Template.ini"
WORK_INI="/root/.config/PrusaSlicer/printer/Job_Current.ini"

cp "$TEMPLATE" "$WORK_INI"
if [ "$MAT" = "pla" ]; then sed -i 's/__NOZZLE__/220/g;s/__BED__/60/g' "$WORK_INI"; 
elif [ "$MAT" = "petg" ]; then sed -i 's/__NOZZLE__/240/g;s/__BED__/70/g' "$WORK_INI"; fi
if [ "$SPEED" = "fast" ]; then sed -i 's/perimeter_speed = 60/perimeter_speed = 120/g;s/solid_infill_speed = 80/solid_infill_speed = 150/g' "$WORK_INI"; fi
if [ "$SUP" = "yes" ]; then sed -i 's/support_material = 0/support_material = 1/g;s/support_material_auto = 0/support_material_auto = 1/g' "$WORK_INI"; fi
prusa-slicer --load "$WORK_INI" --export-gcode --output "$OUTPUT" "$FILE_PATH" 2>&1
SCRIPT
    chmod +x /opt/nexus/laminar.sh

    cat > /opt/nexus/gui.sh << 'SCRIPT'
#!/bin/bash
export DISPLAY=$1
export GALLIUM_DRIVER=llvmpipe
export LIBGL_ALWAYS_SOFTWARE=1
rm -rf /root/.config/PrusaSlicer/cache
fluxbox &
cd /mnt/ia3d/stl_exports
dbus-run-session prusa-slicer
pkill fluxbox
SCRIPT
    chmod +x /opt/nexus/gui.sh

    # --- APP PYTHON ---
    cat > app.py << 'PYTHON'
import os, json, uuid, requests, subprocess, certifi, shutil, re
from flask import Flask, request, jsonify, render_template, send_from_directory

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
        sys_prompt = "Role: OpenSCAD 3D Expert. Rules: 1. Output ONLY valid OpenSCAD code. 2. Wrap code in ```openscad ... ```. 3. Use standard libraries."
        # Lógica de enrutado Dic 2025
        if "gemini" in model:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
            full_prompt = f"{sys_prompt}\n\nContext:\n"
            for m in msgs: full_prompt += f"{m['role'].upper()}: {m['content']}\n"
            r = requests.post(url, json={"contents": [{"parts": [{"text": full_prompt}]}]}, verify=certifi.where(), timeout=30)
            if r.status_code != 200: return f"❌ Error Google ({r.status_code}): {r.text}"
            data = r.json()
            if "candidates" not in data: return f"❌ Bloqueo API: {json.dumps(data)}"
            return data["candidates"][0]["content"]["parts"][0]["text"]
        else:
            # Groq maneja OpenAI OSS y Llama
            url = "https://api.groq.com/openai/v1/chat/completions"
            payload = {"model": model, "messages": [{"role":"system", "content":sys_prompt}] + msgs[-4:], "temperature": 0.1}
            r = requests.post(url, headers={"Authorization": f"Bearer {key}"}, json=payload, verify=certifi.where(), timeout=30)
            if r.status_code != 200: return f"❌ Error Groq ({r.status_code}): {r.text}"
            return r.json()["choices"][0]["message"]["content"]
    except Exception as e: return f"❌ Error Interno: {str(e)}"

@app.route('/')
def index(): return render_template("index.html")

@app.route('/files/<path:filename>')
def download_file(filename): return send_from_directory(STL_DIR, filename)

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
        high_res = "$fa=3; $fs=0.3; $fn=0;\n" + code
        with open(scad, "w") as f: f.write(high_res)
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
    material = request.json.get("material", "pla")
    supports = request.json.get("supports", False)
    path = os.path.join(STL_DIR, f)
    gcode_path = f"{path}.gcode"
    if os.path.exists(gcode_path): os.remove(gcode_path)
    sup_arg = "yes" if supports else "no"
    cmd = ["/bin/bash", "/opt/nexus/laminar.sh", path, speed, material, sup_arg]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True)
        log_output = proc.stdout + proc.stderr
        print_time = "Calculado"
        if os.path.exists(gcode_path):
            try:
                grep_out = subprocess.check_output(f"grep -i '; estimated printing time' '{gcode_path}' | tail -n 1", shell=True).decode()
                if "=" in grep_out: print_time = grep_out.split("=")[1].strip()
            except: pass
            return jsonify({"status": "ok", "msg": f"✅ G-Code Listo\n⏱️ Tiempo: {print_time}"})
        else: return jsonify({"status": "error", "msg": f"Error CLI: {log_output[:500]}"})
    except Exception as e: return jsonify({"status": "error", "msg": str(e)})

@app.route('/api/files')
def files():
    f = []
    if os.path.exists(STL_DIR): 
        for x in os.listdir(STL_DIR):
            if x.endswith(('.stl','.gcode')): f.append({"name": x})
    f.sort(key=lambda k: k['name'], reverse=True)
    return jsonify(f)

@app.route('/api/delete_file', methods=['POST'])
def delete_file():
    f = request.json.get("filename")
    path = os.path.join(STL_DIR, f)
    if os.path.exists(path): os.remove(path); return jsonify({"status": "ok"})
    return jsonify({"status": "error"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYTHON

    # --- FRONTEND 2025: MODELOS ACTUALIZADOS ---
    cat > templates/index.html << 'HTML'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>NEXUS v45 (Dec 2025)</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css">
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/loaders/STLLoader.js"></script>
<script src="https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/controls/OrbitControls.js"></script>

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
    
    .chat-item { display: flex; justify-content: space-between; align-items: center; padding: 8px; border-bottom: 1px solid #333; }
    .file-item { display: flex; align-items: center; padding: 10px; background: #1a1a1a; margin-bottom: 5px; border-radius: 4px; border-left: 4px solid #555; }
    .file-item.stl { border-left-color: #2979ff; }
    .file-item.gcode { border-left-color: #ff9100; }
    .file-icon { width: 40px; height: 40px; background: #333; margin-right: 10px; display: flex; align-items: center; justify-content: center; font-size: 20px; border-radius: 4px; }
    .file-info { flex-grow: 1; overflow: hidden; }
    .file-name { font-size: 0.9em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .file-actions { display: flex; gap: 5px; }
    .btn-mini { width: auto; padding: 5px 10px; font-size: 0.8em; margin: 0; }

    #editorModal, #sliceModal, #previewModal { display:none; position: fixed; top:0; left:0; width:100%; height:100%; background: rgba(0,0,0,0.95); z-index:100; }
    .modal-content { background:#111; margin: 2% auto; padding: 20px; width: 95%; height: 90%; border-radius: 8px; border: 1px solid #00e676; display: flex; flex-direction: column; }
    .small-modal { height: auto; margin: 20% auto; width: 80%; }
    #codeArea { flex: 1; background: #000; color: #0f0; border: 1px solid #333; padding: 10px; font-family: monospace; resize: none; }
    #errorLog { height: 60px; background: #220000; color: #ff5555; border: 1px solid #f00; padding: 5px; overflow-y: auto; font-size: 0.8em; margin-bottom: 10px; display: none; }
    
    #preview-canvas-container { flex: 1; background: #222; border: 1px solid #444; position: relative; width: 100%; height: 100%; overflow: hidden; }
    canvas { display: block; width: 100%; height: 100%; outline: none; }
    
    .controls { position: absolute; top: 10px; right: 10px; z-index: 10; display:flex; gap:5px; }
    .control-btn { width: 40px; height: 40px; background: rgba(0,0,0,0.7); color: white; border: 1px solid #666; border-radius: 4px; cursor: pointer; display:flex; align-items:center; justify-content:center; }
    
    #loadingOverlay { position: absolute; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.8); color:#00e676; display:none; justify-content:center; align-items:center; font-size:1.5em; z-index:20; flex-direction:column;}
    input, select { width: 100%; padding: 10px; background: #222; color: white; border: 1px solid #444; box-sizing: border-box; margin-bottom: 5px; }
</style>
</head>
<body>

<div id="editorModal">
    <div class="modal-content">
        <h3 style="color:#00e676;">🛠️ EDITOR SCAD</h3>
        <div id="errorLog"></div>
        <textarea id="codeArea"></textarea>
        <div style="display:flex; gap:10px; margin-top:10px;">
            <button class="btn-red" onclick="closeEditor()">CERRAR</button>
            <button class="btn-green" onclick="retryCompile()">RECOMPILAR</button>
        </div>
    </div>
</div>

<div id="sliceModal">
    <div class="modal-content small-modal">
        <h3 style="color:#ff9100;">🎲 CONFIGURAR LAMINADO</h3>
        <label>Material:</label>
        <select id="matSelect"><option value="pla">PLA</option><option value="petg">PETG</option></select>
        <label>Opciones:</label>
        <div style="margin-bottom:10px;"><input type="checkbox" id="supCheck" style="width:auto;"> Soporte Orgánico</div>
        <label>Velocidad:</label>
        <select id="speedSelect"><option value="normal">Normal</option><option value="fast">Rápido</option></select>
        <div style="display:flex; gap:10px; margin-top:20px;">
            <button class="btn-red" onclick="$('sliceModal').style.display='none'">CANCELAR</button>
            <button class="btn-orange" onclick="confirmSlice()">LAMINAR</button>
        </div>
    </div>
</div>

<div id="previewModal">
    <div class="modal-content">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:5px;">
            <h3 id="previewTitle" style="color:#2979ff; margin:0;">👁️ VISOR 3D</h3>
            <button class="btn-red" style="width:auto; padding:5px 15px;" onclick="closePreview()">CERRAR</button>
        </div>
        <div id="preview-canvas-container">
            <div id="loadingOverlay"><div>Cargando...</div></div>
            <div class="controls">
                <button class="control-btn" onclick="resetView()">🔄</button>
                <button class="control-btn" onclick="toggleAutoRotate()">⚙️</button>
            </div>
            <canvas id="preview-canvas"></canvas>
        </div>
    </div>
</div>

<button class="btn-green" onclick="launchGUI()">🖥️ ABRIR PRUSA SLICER (GUI)</button>

<div class="box">
    <h3>📂 ARCHIVOS</h3>
    <div id="files">Cargando...</div>
    <button onclick="loadFiles()">🔄 Refrescar</button>
</div>

<div class="box">
    <div style="display:flex; gap:5px;">
        <button onclick="askKey('groq')">🔑 Groq</button>
        <button onclick="askKey('gemini')">🔑 Gemini</button>
    </div>
    <label>SELECCIONAR MODELO (DIC 2025):</label>
    <select id="model">
        <optgroup label="GOOGLE">
            <option value="gemini-3.0">Gemini 3.0 (Nuevo)</option>
            <option value="gemini-2.5-pro">Gemini 2.5 Pro</option>
            <option value="gemini-2.0-flash-exp">Gemini 2.0 Flash</option>
        </optgroup>
        <optgroup label="GROQ (OPEN WEIGHTS)">
            <option value="openai/gpt-oss-120b">OpenAI GPT-OSS 120B (OpenAI 120)</option>
            <option value="llama-3.3-70b-versatile">Llama 3.3 70B</option>
            <option value="mixtral-8x7b-32768">Mixtral 8x7B</option>
        </optgroup>
    </select>
    <div style="display:flex;justify-content:space-between;align-items:center;">
        <span>CHATS:</span><button onclick="newC()" style="width:auto;padding:5px;">+</button>
    </div>
    <div id="chats" style="max-height:100px;overflow-y:auto;margin-top:5px;"></div>
</div>

<div class="box">
    <div id="messages"></div>
    <div style="display:flex; gap:5px;">
        <input id="in" placeholder="Escribe..." onkeypress="if(event.key=='Enter') send()">
        <button onclick="send()" style="width:50px;">➤</button>
    </div>
</div>

<script>
let cid = null; let currentStl = null;
const $ = id => document.getElementById(id);

// --- 3D VIEWER ---
let scene, camera, renderer, controls, mesh = null, gcodeGroup = null;
let autoRotate = false;

function init3D() {
    const canvas = $('preview-canvas');
    scene = new THREE.Scene(); scene.background = new THREE.Color(0x111111);
    camera = new THREE.PerspectiveCamera(50, canvas.clientWidth / canvas.clientHeight, 0.1, 2000);
    camera.position.set(0, 100, 200);
    renderer = new THREE.WebGLRenderer({ canvas: canvas, antialias: true, alpha: true });
    renderer.setSize(canvas.clientWidth, canvas.clientHeight);
    controls = new THREE.OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    scene.add(new THREE.AmbientLight(0xffffff, 0.6));
    const dl = new THREE.DirectionalLight(0xffffff, 0.8); dl.position.set(100, 100, 100); scene.add(dl);
    scene.add(new THREE.GridHelper(200, 20, 0x444444, 0x222222));
    scene.add(new THREE.AxesHelper(20));
    animate();
}

function animate() {
    requestAnimationFrame(animate);
    if(controls) controls.update();
    if(autoRotate && (mesh || gcodeGroup)) scene.rotation.y += 0.005; else scene.rotation.y = 0;
    renderer.render(scene, camera);
}

function clearScene() {
    if(mesh) { scene.remove(mesh); mesh.geometry.dispose(); mesh = null; }
    if(gcodeGroup) { scene.remove(gcodeGroup); gcodeGroup = null; }
    scene.rotation.set(0,0,0);
}

function loadSTL(filename) {
    clearScene(); $('loadingOverlay').style.display = 'flex';
    new THREE.STLLoader().load(`/files/${filename}`, (geo) => {
        const mat = new THREE.MeshPhongMaterial({ color: 0x2979ff, specular: 0x111111, shininess: 200 });
        mesh = new THREE.Mesh(geo, mat);
        geo.computeBoundingBox();
        const center = geo.boundingBox.getCenter(new THREE.Vector3());
        geo.translate(-center.x, -center.y, -center.z); 
        const size = geo.boundingBox.getSize(new THREE.Vector3());
        mesh.position.y = size.y / 2;
        scene.add(mesh);
        const maxDim = Math.max(size.x, size.y, size.z);
        camera.position.set(maxDim*1.5, maxDim*1.5, maxDim*2); controls.target.set(0,0,0);
        $('loadingOverlay').style.display = 'none'; $('previewTitle').innerText = "STL: " + filename;
    });
}

async function loadGCode(filename) {
    clearScene(); $('loadingOverlay').style.display = 'flex';
    try {
        const txt = await (await fetch(`/files/${filename}`)).text();
        const matEx = new THREE.LineBasicMaterial({ color: 0xff9100 });
        const matTr = new THREE.LineBasicMaterial({ color: 0x0044aa, opacity: 0.3, transparent: true });
        const pEx = [], pTr = [];
        let x=0, y=0, z=0, lx=0, ly=0, lz=0;
        
        for(let line of txt.split('\n')) {
            line = line.trim();
            if(line.startsWith('G0') || line.startsWith('G1')) {
                const args = line.split(' ');
                let nx=x, ny=y, nz=z, mov=false;
                for(let a of args) {
                    const c = a.charAt(0); const v = parseFloat(a.substring(1));
                    if(c==='X'){nx=v;mov=true;} if(c==='Y'){ny=v;mov=true;} if(c==='Z'){nz=v;mov=true;}
                }
                if(mov) {
                    if(line.includes('E') && !line.endsWith('E0')) pEx.push(lx,lz,ly,nx,nz,ny);
                    else if(Math.abs(nx-lx)>0.1 || Math.abs(ny-ly)>0.1) pTr.push(lx,lz,ly,nx,nz,ny);
                    lx=nx; ly=ny; lz=nz; x=nx; y=ny; z=nz;
                }
            }
        }
        gcodeGroup = new THREE.Group();
        if(pEx.length) { const g=new THREE.BufferGeometry(); g.setAttribute('position',new THREE.Float32BufferAttribute(pEx,3)); gcodeGroup.add(new THREE.LineSegments(g,matEx)); }
        if(pTr.length) { const g=new THREE.BufferGeometry(); g.setAttribute('position',new THREE.Float32BufferAttribute(pTr,3)); gcodeGroup.add(new THREE.LineSegments(g,matTr)); }
        
        const b = new THREE.Box3().setFromObject(gcodeGroup);
        const c = b.getCenter(new THREE.Vector3());
        gcodeGroup.position.x = -c.x; gcodeGroup.position.z = -c.z;
        scene.add(gcodeGroup);
        camera.position.set(150, 150, 150); controls.target.set(0,0,0);
        $('previewTitle').innerText = "GCODE: " + filename;
    } catch(e) { alert("Error G-Code"); }
    $('loadingOverlay').style.display = 'none';
}

async function openPreview(f, t) { $('previewModal').style.display='block'; if(!scene) init3D(); if(t=='stl') loadSTL(f); else loadGCode(f); }
function closePreview() { $('previewModal').style.display='none'; clearScene(); }
function resetView() { controls.reset(); }
function toggleAutoRotate() { autoRotate = !autoRotate; }

// --- UI LOGIC ---
function openEditor(code, err=null) { $('editorModal').style.display='block'; $('codeArea').value=code; if(err){$('errorLog').style.display='block';$('errorLog').innerText=err;}else $('errorLog').style.display='none'; }
function closeEditor() { $('editorModal').style.display='none'; }
function openSliceModal(f) { currentStl=f; $('sliceModal').style.display='block'; }

async function confirmSlice() {
    $('sliceModal').style.display='none';
    const btn = document.querySelector(`button[onclick="openSliceModal('${currentStl}')"]`); if(btn) btn.innerHTML="⏳";
    const d = await api('/api/slice_file', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({filename:currentStl, speed:$('speedSelect').value, material:$('matSelect').value, supports:$('supCheck').checked})});
    alert(d.msg); loadFiles();
}

async function api(url, opts={}) { try { const r=await fetch(url,opts); return await r.json(); } catch(e) { return {error:e.message}; } }
async function launchGUI() { await api('/api/launch_gui', {method:'POST'}); alert("X11 iniciado"); }

async function loadFiles() {
    const f = await api('/api/files');
    $('files').innerHTML = f.map(x => {
        let t = x.name.endsWith('.gcode')?'gcode':'stl';
        let acts = t=='stl' ? `<button class="btn-mini btn-blue" onclick="openSliceModal('${x.name}')">🔪</button><button class="btn-mini btn-blue" onclick="openPreview('${x.name}','stl')">👁️</button>` : `<button class="btn-mini btn-orange" onclick="openPreview('${x.name}','gcode')">👁️</button>`;
        return `<div class="file-item ${t}"><div class="file-icon">${t=='gcode'?'🖨️':'🧊'}</div><div class="file-info"><div class="file-name">${x.name}</div></div><div class="file-actions">${acts}<a href="/files/${x.name}" download><button class="btn-mini btn-blue">⬇️</button></a><button class="btn-mini btn-red" onclick="delF('${x.name}')">🗑️</button></div></div>`;
    }).join('') || '<div style="text-align:center;color:#555">Vacío</div>';
}

async function delF(f) { if(confirm(`Borrar ${f}?`)) { await api('/api/delete_file', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({filename:f})}); loadFiles(); } }
async function retryCompile() { const c=$('codeArea').value; const n=prompt("Guardar como:","fixed"); if(!n) return; const d=await api('/api/compile_scad',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code:c,filename:n})}); if(d.status=='ok'){alert('OK');closeEditor();loadFiles();} else $('errorLog').innerText=d.msg; }
async function comp(c) { const n=prompt("Nombre STL:","ia_part"); if(!n) return; const d=await api('/api/compile_scad',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code:c,filename:n})}); if(d.status=='ok'){alert('OK');loadFiles();} else openEditor(c,d.msg); }

async function send() {
    const t=$('in').value; if(!t||!cid) return; $('in').value=''; appendMsg({role:'user',content:t});
    const d=await api(`/api/chats/${cid}/message`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({content:t})});
    appendMsg({role:'assistant',content:d.reply||d.error});
}
function appendMsg(m) {
    const d=document.createElement('div'); d.className=`msg ${m.role}`; d.innerHTML=marked.parse(m.content);
    if(m.content.includes('```openscad')) {
        const c = m.content.match(/```openscad([\s\S]*?)```/)[1].trim().replace(/`/g,'\\`').replace(/"/g,'&quot;');
        d.innerHTML+=`<div style="margin-top:10px;display:flex;gap:5px;"><button onclick='comp(\`${c}\`)' class="btn-green">⚙️ STL</button><button onclick='openEditor(\`${c}\`)' class="btn-blue">✏️ EDIT</button></div>`;
    }
    $('messages').appendChild(d); $('messages').scrollTop=99999;
}
async function newC() { const t=prompt("Chat:"); if(!t) return; const d=await api('/api/chats',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({title:t,model:$('model').value})}); cid=d.chat_id; loadChats(); $('messages').innerHTML=''; }
async function loadChats() { const d=await api('/api/chats'); $('chats').innerHTML=d.map(c=>`<div class="chat-item" onclick="load('${c.chat_id}')"><span>${c.title}</span><span style="font-size:0.7em;color:#666">${c.model.split('-')[1]}</span></div>`).join(''); }
async function load(id) { cid=id; const d=await api(`/api/chats/${id}`); $('messages').innerHTML=''; d.messages.forEach(appendMsg); }
async function askKey(t) { const k=prompt(`Key ${t}:`); if(k) api('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({[t+'ApiKey']:k})}); }

loadChats(); loadFiles();
</script>
</body>
</html>
HTML
EOF
}

setup_environment
inject_fusion_server

echo -e "${G}╔════════════════════════════════════════════╗${NC}"
echo -e "${G}║   NEXUS v45.1: 2025 MODEL UPDATE READY     ║${NC}"
echo -e "${G}╚════════════════════════════════════════════╝${NC}"
echo -e "${Y}>> http://localhost:5000${NC}"

proot-distro login ubuntu --bind "$IA3D_ROOT:/mnt/ia3d" --shared-tmp -- bash -c "cd /opt/nexus; source venv/bin/activate; python3 -u app.py" &

( while true; do
    if [ -f "$TRIGGER_FILE" ]; then
        rm -f "$TRIGGER_FILE"; am force-stop com.termux.x11 >/dev/null 2>&1; pkill -9 -f termux-x11
        rm -rf $PREFIX/tmp/.X11-unix; mkdir -p $PREFIX/tmp/.X11-unix; chmod 1777 $PREFIX/tmp/.X11-unix
        D=$((10 + RANDOM % 90)); termux-x11 :$D -ac &
        while [ ! -S "$PREFIX/tmp/.X11-unix/X$D" ]; do sleep 0.1; done
        am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1
        proot-distro login ubuntu --bind "$IA3D_ROOT:/mnt/ia3d" --shared-tmp -- bash -c "/opt/nexus/gui.sh :$D" &
    fi; sleep 1; done ) &
wait
