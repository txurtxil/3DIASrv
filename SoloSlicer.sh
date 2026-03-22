cat << 'EOF_SCRIPT' > srv.sh
#!/bin/bash
# ==========================================
# NEXUS WEBOS v50: PURE CAD STUDIO
# ==========================================
# Motor: OpenSCAD + PrusaSlicer (A1 Mini)
# Sin APIs IA externas. Solo compilación.
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
        pkg install termux-x11-nightly proot-distro python -y
    fi
    if [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" ]; then proot-distro install ubuntu; fi
}

inject_fusion_server() {
    echo -e "${C}[*] Configurando Estudio CAD Purificado...${NC}"
    
    proot-distro login ubuntu --bind "$IA3D_ROOT:/mnt/ia3d" --shared-tmp -- bash << 'EOF'
    export DEBIAN_FRONTEND=noninteractive
    
    apt update -q
    apt install -y python3 python3-pip python3-venv fluxbox prusa-slicer \
                   openscad dbus-x11 procps mesa-utils grep sed
    
    mkdir -p /root/.fluxbox
    echo "session.screen0.toolbar.visible: false" > /root/.fluxbox/init
    
    # --- PRUSA SLICER CONFIG: BAMBU LAB A1 MINI ---
    mkdir -p /root/.config/PrusaSlicer/printer
    cat > /root/.config/PrusaSlicer/printer/Bambu_A1_Mini.ini << 'INI'
[printer:Bambu_A1_Mini]
bed_shape = 0x0,180x0,180x180,0x180
max_print_height = 180
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
perimeter_speed = 150
small_perimeter_speed = 80
solid_infill_speed = 150
top_solid_infill_speed = 100
travel_speed = 400
first_layer_speed = 40
fill_density = 15%
fill_pattern = gyroid
support_material = 0
support_material_style = organic
support_material_auto = 0
start_gcode = M104 S__NOZZLE__\nM140 S__BED__\nG28\nM190 S__BED__\nM109 S__NOZZLE__\nG90\nG1 Z5 F3000\nG1 X2 Y5 F3000\nG1 Z0.2 F300\nG1 Y85 E12 F1000\nG1 Y165 E12 F1000\nG1 Z5 F3000\nG92 E0\n
end_gcode = M104 S0\nM140 S0\nG91\nG1 E-2 Z5 F3000\nG90\nG1 X0 Y180 F3000\nM84
INI

    mkdir -p /root/.config/PrusaSlicer
    echo -e "[App]\nview_mode = expert\nversion_check = 0\nshow_splash_screen = 0" > /root/.config/PrusaSlicer/PrusaSlicer.ini

    mkdir -p /opt/nexus /mnt/ia3d/stl_exports
    cd /opt/nexus
    mkdir -p templates
    if [ ! -d "venv" ]; then python3 -m venv venv; ./venv/bin/pip install flask; fi

    cat > /opt/nexus/laminar.sh << 'SCRIPT'
#!/bin/bash
FILE_PATH="$1"
SPEED="$2"
MAT="$3"
SUP="$4"
OUTPUT="${FILE_PATH}.gcode"
TEMPLATE="/root/.config/PrusaSlicer/printer/Bambu_A1_Mini.ini"
WORK_INI="/root/.config/PrusaSlicer/printer/Job_Current.ini"

cp "$TEMPLATE" "$WORK_INI"
if [ "$MAT" = "pla" ]; then sed -i 's/__NOZZLE__/220/g;s/__BED__/65/g' "$WORK_INI"; 
elif [ "$MAT" = "petg" ]; then sed -i 's/__NOZZLE__/250/g;s/__BED__/75/g' "$WORK_INI"; fi
if [ "$SPEED" = "fast" ]; then sed -i 's/perimeter_speed = 150/perimeter_speed = 200/g;s/solid_infill_speed = 150/solid_infill_speed = 200/g' "$WORK_INI"; fi
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

    cat > app.py << 'PYTHON'
import os, subprocess, re
from flask import Flask, request, jsonify, render_template, send_from_directory

DATA_DIR = "/mnt/ia3d"
STL_DIR = os.path.join(DATA_DIR, "stl_exports")
TRIGGER_PATH = os.path.join(DATA_DIR, ".trigger_gui")

app = Flask(__name__)
app.config['SEND_FILE_MAX_AGE_DEFAULT'] = 0

@app.after_request
def add_header(response):
    response.headers['Cache-Control'] = 'no-store'
    return response

@app.route('/')
def index(): return render_template("index.html")

@app.route('/files/<path:filename>')
def download_file(filename): return send_from_directory(STL_DIR, filename)

@app.route('/api/compile_scad', methods=['POST'])
def compile():
    code = request.json.get("code")
    raw_name = request.json.get("filename", "Pieza_Custom")
    safe_name = re.sub(r'[^a-zA-Z0-9_-]', '_', raw_name)
    scad = os.path.join(STL_DIR, f"{safe_name}.scad")
    stl = os.path.join(STL_DIR, f"{safe_name}.stl")
    try:
        if "$fn" not in code: code = "$fn=100;\n" + code
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
            if x.endswith(('.stl','.gcode', '.scad')): f.append({"name": x})
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

    cat > templates/index.html << 'HTML'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>NEXUS STUDIO CAD</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/loaders/STLLoader.js"></script>
<script src="https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/controls/OrbitControls.js"></script>

<style>
    body { background: #0a0a0a; color: #eee; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; padding: 10px; margin: 0; display: flex; flex-direction: column; height: 100vh; }
    h2, h3 { margin-top: 0; color: #00e676; }
    
    .workspace { display: flex; flex-direction: column; gap: 10px; flex: 1; min-height: 0; }
    @media (min-width: 768px) { .workspace { flex-direction: row; } }
    
    .panel { background: #151515; border: 1px solid #333; border-radius: 8px; padding: 15px; display: flex; flex-direction: column; }
    .editor-panel { flex: 1; }
    .files-panel { flex: 1; overflow-y: auto; }
    
    textarea { flex: 1; background: #000; color: #00ff00; border: 1px solid #444; padding: 10px; font-family: monospace; font-size: 14px; resize: none; border-radius: 4px; margin-bottom: 10px; outline: none; }
    
    button { padding: 12px; font-weight: bold; cursor: pointer; border: none; border-radius: 4px; color: #000; transition: 0.2s; }
    button:hover { opacity: 0.8; transform: scale(0.98); }
    .btn-green { background: #00e676; }
    .btn-blue { background: #2979ff; color: white; }
    .btn-orange { background: #ff9100; }
    .btn-red { background: #ff1744; color: white; }
    
    #errorLog { background: #3a0000; color: #ff5555; border: 1px solid #ff0000; padding: 10px; margin-bottom: 10px; display: none; font-family: monospace; border-radius: 4px; white-space: pre-wrap; max-height: 150px; overflow-y: auto; }
    
    .file-item { display: flex; justify-content: space-between; align-items: center; padding: 10px; background: #222; margin-bottom: 5px; border-radius: 4px; border-left: 4px solid #555; }
    .file-item.stl { border-left-color: #2979ff; }
    .file-item.gcode { border-left-color: #ff9100; }
    .file-item.scad { border-left-color: #00e676; }
    .file-name { font-weight: bold; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 50%; }
    .file-actions { display: flex; gap: 5px; }
    .btn-mini { padding: 5px 10px; font-size: 12px; }

    #sliceModal, #previewModal { display:none; position: fixed; top:0; left:0; width:100%; height:100%; background: rgba(0,0,0,0.95); z-index:100; }
    .modal-content { background:#111; margin: 5% auto; padding: 20px; width: 90%; max-width: 600px; border-radius: 8px; border: 1px solid #555; display: flex; flex-direction: column; }
    .preview-modal-content { width: 95%; height: 90%; max-width: none; }
    
    #preview-canvas-container { flex: 1; background: #222; border: 1px solid #444; position: relative; width: 100%; height: 100%; overflow: hidden; border-radius: 4px; }
    canvas { display: block; width: 100%; height: 100%; outline: none; }
    .controls { position: absolute; top: 10px; right: 10px; z-index: 10; display:flex; gap:5px; }
    .control-btn { background: rgba(0,0,0,0.7); color: white; border: 1px solid #666; padding: 10px; border-radius: 4px; cursor: pointer; }
    
    select, input { width: 100%; padding: 10px; background: #222; color: white; border: 1px solid #444; border-radius: 4px; margin-bottom: 15px; box-sizing: border-box; }
</style>
</head>
<body>

<div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 10px;">
    <h2>NEXUS STUDIO CAD</h2>
    <button class="btn-blue" style="padding: 8px 15px;" onclick="launchGUI()">🖥️ PrusaSlicer GUI</button>
</div>

<div class="workspace">
    <div class="panel editor-panel">
        <h3>📝 Código OpenSCAD</h3>
        <div id="errorLog"></div>
        <textarea id="codeArea" placeholder="// Pega aquí el código OpenSCAD generado por Gemini..." spellcheck="false"></textarea>
        <button class="btn-green" onclick="compileCode()">⚙️ COMPILAR A STL</button>
    </div>

    <div class="panel files-panel">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 10px;">
            <h3 style="margin:0;">📂 Archivos</h3>
            <button class="btn-mini btn-blue" onclick="loadFiles()">🔄 Actualizar</button>
        </div>
        <div id="filesList">Cargando...</div>
    </div>
</div>

<div id="sliceModal">
    <div class="modal-content">
        <h3 style="color:#ff9100; margin-top:0;">🎲 LAMINAR PARA A1 MINI</h3>
        <p id="sliceFileName" style="color:#888; font-family:monospace; margin-bottom:15px;"></p>
        
        <label>Material:</label>
        <select id="matSelect"><option value="pla">PLA</option><option value="petg">PETG</option></select>
        
        <label>Calidad / Velocidad:</label>
        <select id="speedSelect"><option value="fast">Rápido (A1 Mini FDM)</option><option value="normal">Detalle Alto</option></select>
        
        <div style="margin-bottom:20px; display:flex; align-items:center; gap:10px;">
            <input type="checkbox" id="supCheck" style="width:auto; transform:scale(1.5);"> 
            <label for="supCheck">Generar Soportes Orgánicos</label>
        </div>
        
        <div style="display:flex; gap:10px;">
            <button class="btn-red" style="flex:1;" onclick="$('sliceModal').style.display='none'">CANCELAR</button>
            <button class="btn-orange" style="flex:2;" onclick="confirmSlice()">🔪 LAMINAR AHORA</button>
        </div>
    </div>
</div>

<div id="previewModal">
    <div class="modal-content preview-modal-content">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
            <h3 id="previewTitle" style="color:#2979ff; margin:0;">👁️ VISOR 3D</h3>
            <button class="btn-red btn-mini" onclick="closePreview()">CERRAR</button>
        </div>
        <div id="preview-canvas-container">
            <div class="controls">
                <button class="control-btn" onclick="controls.reset()">🔄 Reset View</button>
            </div>
            <canvas id="preview-canvas"></canvas>
        </div>
    </div>
</div>

<script>
let currentStl = null;
const $ = id => document.getElementById(id);

// --- COMPILACIÓN ---
async function compileCode() {
    const code = $('codeArea').value.trim();
    if(!code) return alert("Pega código OpenSCAD primero.");
    
    const filename = prompt("Guardar pieza como (sin espacios):", "pieza_01");
    if(!filename) return;

    $('errorLog').style.display = 'none';
    const res = await fetch('/api/compile_scad', {
        method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({code: code, filename: filename})
    });
    const data = await res.json();
    
    if(data.status === 'ok') {
        alert("✅ STL Generado Correctamente");
        loadFiles();
    } else {
        $('errorLog').style.display = 'block';
        $('errorLog').innerText = "[ERROR DE OPENSCAD]\n" + data.msg;
    }
}

// --- GESTIÓN DE ARCHIVOS ---
async function loadFiles() {
    const res = await fetch('/api/files');
    const files = await res.json();
    
    $('filesList').innerHTML = files.map(x => {
        let type = x.name.split('.').pop();
        let acts = '';
        if(type === 'scad') {
            acts = `<button class="btn-mini btn-green" onclick="loadScad('${x.name}')">✏️ Cargar</button>`;
        } else if(type === 'stl') {
            acts = `<button class="btn-mini btn-orange" onclick="openSliceModal('${x.name}')">🔪 Laminar</button>
                    <button class="btn-mini btn-blue" onclick="openPreview('${x.name}','stl')">👁️ 3D</button>`;
        } else if(type === 'gcode') {
            acts = `<button class="btn-mini btn-orange" onclick="openPreview('${x.name}','gcode')">👁️ G-Code</button>`;
        }
        
        return `<div class="file-item ${type}">
            <div class="file-name" title="${x.name}">${x.name}</div>
            <div class="file-actions">
                ${acts}
                <a href="/files/${x.name}" download><button class="btn-mini btn-blue">⬇️</button></a>
                <button class="btn-mini btn-red" onclick="deleteFile('${x.name}')">🗑️</button>
            </div>
        </div>`;
    }).join('') || '<div style="color:#666; text-align:center; padding:20px;">No hay archivos generados.</div>';
}

async function loadScad(filename) {
    const res = await fetch(`/files/${filename}`);
    const text = await res.text();
    $('codeArea').value = text;
}

async function deleteFile(filename) {
    if(!confirm(`¿Borrar ${filename}?`)) return;
    await fetch('/api/delete_file', {
        method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({filename: filename})
    });
    loadFiles();
}

// --- LAMINADOR ---
function openSliceModal(filename) { 
    currentStl = filename; 
    $('sliceFileName').innerText = filename;
    $('sliceModal').style.display = 'block'; 
}

async function confirmSlice() {
    $('sliceModal').style.display = 'none';
    const res = await fetch('/api/slice_file', {
        method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
            filename: currentStl, 
            speed: $('speedSelect').value, 
            material: $('matSelect').value, 
            supports: $('supCheck').checked
        })
    });
    const data = await res.json();
    alert(data.msg);
    loadFiles();
}

async function launchGUI() {
    await fetch('/api/launch_gui', {method: 'POST'});
    alert("PrusaSlicer abriéndose en la app Termux:X11...");
}

// --- VISOR 3D ---
let scene, camera, renderer, controls, currentMesh = null;

function init3D() {
    const canvas = $('preview-canvas');
    scene = new THREE.Scene(); scene.background = new THREE.Color(0x111111);
    camera = new THREE.PerspectiveCamera(50, canvas.clientWidth / canvas.clientHeight, 0.1, 2000);
    renderer = new THREE.WebGLRenderer({ canvas: canvas, antialias: true });
    renderer.setSize(canvas.clientWidth, canvas.clientHeight);
    controls = new THREE.OrbitControls(camera, renderer.domElement);
    
    scene.add(new THREE.AmbientLight(0xffffff, 0.6));
    const dl = new THREE.DirectionalLight(0xffffff, 0.8); dl.position.set(100, 100, 100); scene.add(dl);
    scene.add(new THREE.GridHelper(200, 20, 0x444444, 0x222222));
    
    function animate() { requestAnimationFrame(animate); controls.update(); renderer.render(scene, camera); }
    animate();
}

function openPreview(filename, type) {
    $('previewModal').style.display = 'block';
    $('previewTitle').innerText = filename;
    if(!scene) init3D();
    if(currentMesh) { scene.remove(currentMesh); }
    
    if(type === 'stl') {
        new THREE.STLLoader().load(`/files/${filename}`, (geo) => {
            geo.center();
            const mat = new THREE.MeshPhongMaterial({ color: 0x00e676, specular: 0x111111, shininess: 100 });
            currentMesh = new THREE.Mesh(geo, mat);
            scene.add(currentMesh);
            camera.position.set(150, 150, 150); controls.target.set(0,0,0);
        });
    } else {
        // Simple G-code viewer
        fetch(`/files/${filename}`).then(r => r.text()).then(txt => {
            const matEx = new THREE.LineBasicMaterial({ color: 0xff9100 });
            const pts = []; let x=0, y=0, z=0, lx=0, ly=0, lz=0;
            txt.split('\n').forEach(line => {
                if(line.startsWith('G1') && line.includes('E') && !line.includes('E-')) {
                    const args = line.split(' ');
                    args.forEach(a => { if(a[0]=='X') x=parseFloat(a.substring(1)); if(a[0]=='Y') y=parseFloat(a.substring(1)); if(a[0]=='Z') z=parseFloat(a.substring(1)); });
                    pts.push(lx,lz,ly, x,z,y); lx=x; ly=y; lz=z;
                } else if (line.startsWith('G0') || line.startsWith('G1')) {
                    const args = line.split(' ');
                    args.forEach(a => { if(a[0]=='X') lx=x=parseFloat(a.substring(1)); if(a[0]=='Y') ly=y=parseFloat(a.substring(1)); if(a[0]=='Z') lz=z=parseFloat(a.substring(1)); });
                }
            });
            const geo = new THREE.BufferGeometry(); geo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
            currentMesh = new THREE.LineSegments(geo, matEx);
            
            // Center G-code
            geo.computeBoundingBox(); const center = geo.boundingBox.getCenter(new THREE.Vector3());
            currentMesh.position.set(-center.x, -center.y, -center.z);
            
            scene.add(currentMesh);
            camera.position.set(150, 150, 150); controls.target.set(0,0,0);
        });
    }
}
function closePreview() { $('previewModal').style.display = 'none'; }

// Init
window.addEventListener('resize', () => { if(camera && renderer) { camera.aspect = $('preview-canvas').clientWidth / $('preview-canvas').clientHeight; camera.updateProjectionMatrix(); renderer.setSize($('preview-canvas').clientWidth, $('preview-canvas').clientHeight); } });
loadFiles();
</script>
</body>
</html>
HTML
EOF
}

setup_environment
inject_fusion_server

echo -e "${C}╔════════════════════════════════════════════╗${NC}"
echo -e "${C}║ NEXUS v50: PURE CAD STUDIO                 ║${NC}"
echo -e "${C}╚════════════════════════════════════════════╝${NC}"
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
EOF_SCRIPT

chmod +x srv.sh
