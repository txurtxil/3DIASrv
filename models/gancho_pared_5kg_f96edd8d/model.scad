// REGLA 4: Definición de resolución para las curvas
$fn=24;

// --- PARÁMETROS DE DISEÑO ---

// Dimensiones de la base de pared
base_ancho = 30;
base_alto = 65;
base_grosor = 4;        // REGLA 3: Mínimo 2mm
base_radio_esquina = 8;

// Dimensiones del brazo del gancho
gancho_ancho = 12;      // Ancho del brazo (eje X) para mayor robustez
gancho_alcance = 38;    // Cuánto sobresale de la pared (eje Y)
gancho_grosor_brazo = 8; // Grosor del brazo principal
gancho_radio_int = 15;  // Radio interior de la curva

// Dimensiones del refuerzo inferior (Gusset)
refuerzo_alto = 28;     // Altura del refuerzo sobre la base
refuerzo_alcance = 22;  // Alcance del refuerzo desde la base

// Parámetros de los agujeros (diseñados para tornillos M4)
tornillo_dist_z = 45;
tornillo_diam = 4.5;
avellanado_diam = 9;
avellanado_prof = 3;


// --- CÁLCULOS INTERNOS ---
// REGLA 2: Cálculo del desplazamiento para centrar el objeto en (0,0,0)
max_y = base_grosor + gancho_alcance;
min_y = 0;
desplazamiento_y = -(max_y + min_y) / 2;


// --- CONSTRUCCIÓN DEL MODELO ---
translate([0, desplazamiento_y, 0]) {
    difference() {
        union() {
            // Parte 1: Base de la pared
            // Se construye extruyendo una forma 2D con esquinas redondeadas.
            // REGLA 5: Comentario de parte clave
            linear_extrude(height = base_grosor) {
                offset(r = base_radio_esquina) {
                    square([base_ancho - 2*base_radio_esquina, base_alto - 2*base_radio_esquina], center = true);
                }
            }

            // Parte 2: Brazo del gancho y refuerzo
            // Se extruye un perfil 2D único para máxima solidez (FDM friendly).
            // REGLA 5: Comentario de parte clave
            translate([-gancho_ancho/2, 0, 0]) {
                linear_extrude(height = gancho_ancho, center = false) {
                    // El perfil 2D se crea con un 'hull' de varias formas simples
                    // para generar una geometría orgánica y resistente.
                    hull() {
                        // Conexión vertical con la base
                        translate([0, -refuerzo_alto])
                        square([base_grosor, refuerzo_alto + gancho_grosor_brazo]);

                        // Refuerzo triangular (Gusset)
                        polygon(points=[
                            [base_grosor, -refuerzo_alto],
                            [base_grosor, 0],
                            [base_grosor + refuerzo_alcance, 0]
                        ]);
                        
                        // Brazo horizontal
                        translate([base_grosor, 0])
                        square([gancho_alcance - gancho_radio_int, gancho_grosor_brazo]);
                        
                        // Círculo en el extremo para formar la curva y la punta
                        translate([base_grosor + gancho_alcance - gancho_radio_int, gancho_radio_int + gancho_grosor_brazo])
                        circle(r=gancho_grosor_brazo + 2);
                    }
                }
            }
        }

        // Parte 3: Agujeros avellanados para los tornillos
        // Se posicionan en la cara frontal de la base para realizar la sustracción.
        // REGLA 5: Comentario de parte clave
        // Agujero superior
        translate([0, base_grosor, tornillo_dist_z/2]) {
            rotate([-90, 0, 0]) {
                // Cilindro pasante
                cylinder(h = base_grosor + 2, d = tornillo_diam, center=true);
                // Cilindro cónico para el avellanado
                cylinder(h = avellanado_prof, d1 = avellanado_diam, d2 = tornillo_diam);
            }
        }
        // Agujero inferior
        translate([0, base_grosor, -tornillo_dist_z/2]) {
            rotate([-90, 0, 0]) {
                // Cilindro pasante
                cylinder(h = base_grosor + 2, d = tornillo_diam, center=true);
                // Cilindro cónico para el avellanado
                cylinder(h = avellanado_prof, d1 = avellanado_diam, d2 = tornillo_diam);
            }
        }
    }
}