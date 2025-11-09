// Dock multifuncional para Google Pixel 10
// compatible con OpenSCAD 2021+

// REGLA 4: $fn=24 en curvas
$fn = 24;

// REGLA 3: Paredes minimas 2mm
wall = 2;

// --- Dimensiones del Telefono (Pixel 10) ---
phone_w = 70;
phone_h = 145;
phone_t = 9; // Espesor del hueco para el telefono (con holgura)

// --- Geometria del Soporte del Telefono ---
stand_angle = 65;
lip_h = 15; // Altura del borde frontal
cable_slot_w = 10;
cable_slot_d = 5;

// --- Geometria del Soporte del Reloj ---
watch_w = 50;
watch_h = 40;
watch_d = 45; // Profundidad del hueco

// --- Geometria del Organizador de Boligrafos ---
pen_organizer_h = 80;
pen_organizer_d = 40;
pen_slot_w = 10;
pen_slots = 4;

// --- Calculos de Dimensiones Totales ---
phone_section_w = phone_w + 2 * wall;
accessory_section_w = watch_w + 2 * wall;
total_w = phone_section_w + wall + accessory_section_w;
total_d = 100;
back_rest_h = phone_h * sin(stand_angle) + 5; // Altura del respaldo inclinado

// REGLA 2: Centrado en (0,0,0)
translate([-total_w / 2, -total_d / 2, 0]) {
    difference() {
        // --- CUERPO SOLIDO PRINCIPAL ---
        // REGLA 5: Usa comentarios // para partes clave
        union() {
            // Base principal con esquinas redondeadas
            hull() {
                for (x = [wall, total_w - wall]) {
                    for (y = [wall, total_d - wall]) {
                        translate([x, y, 0]) cylinder(h = 5, r = wall);
                    }
                }
            }
            
            // Respaldo inclinado para el telefono
            translate([0, total_d - wall, 0]) {
                rotate([-(90 - stand_angle), 0, 0]) {
                    cube([phone_section_w, wall, back_rest_h]);
                }
            }
            
            // Borde frontal que sujeta el telefono
            lip_y_pos = total_d - (lip_h / tan(stand_angle)) - wall * 2;
            translate([wall, lip_y_pos, 0]) {
                cube([phone_w, wall * 2, lip_h]);
            }
            
            // Bloque lateral para reloj y boligrafos
            translate([phone_section_w + wall, 0, 0]) {
                cube([accessory_section_w, pen_organizer_d, pen_organizer_h]);
            }
        }

        // --- HUECOS Y CORTES ---
        union() {
            // Hueco para el telefono (define las "pinzas" laterales)
            phone_cutout_y = total_d - (lip_h / tan(stand_angle)) - wall;
            translate([wall, phone_cutout_y, 0]) {
                rotate([-(90 - stand_angle), 0, 0]) {
                    // Volumen principal del telefono a sustraer
                    translate([0, -phone_t, lip_h]) {
                        cube([phone_w, phone_t, phone_h + 10]);
                    }
                    // Curva superior para evitar la camara
                    translate([phone_w / 2, -phone_t, phone_h - 15]) {
                        rotate([0, 90, 0]) {
                            cylinder(h = phone_w + 2, r = 25, center = true);
                        }
                    }
                }
            }

            // Ranura para el cable de carga
            translate([(phone_section_w - cable_slot_w) / 2, 0, -1]) {
                // Corte horizontal en la base
                cube([cable_slot_w, total_d, cable_slot_d + 2]);
                // Corte vertical a traves del borde frontal
                translate([0, lip_y_pos, 0]) {
                    cube([cable_slot_w, wall * 2 + 1, lip_h + 2]);
                }
            }
            
            // Compartimento para el reloj inteligente
            watch_cutout_x = phone_section_w + wall + wall;
            translate([watch_cutout_x, -1, wall]) { // -1 en Y para asegurar el corte
                 hull() {
                    translate([watch_w / 2, wall, 0]) cylinder(h = watch_h, r = watch_w / 2);
                    translate([watch_w / 2, watch_d, 0]) cylinder(h = watch_h, r = watch_w / 2);
                 }
            }

            // Organizador de boligrafos
            pen_section_inner_w = accessory_section_w - 2 * wall;
            pen_section_inner_d = pen_organizer_d - 2 * wall;
            slots_total_w = pen_slots * pen_slot_w + (pen_slots - 1) * wall;
            slots_start_x = phone_section_w + wall + wall + (pen_section_inner_w - slots_total_w) / 2;
            slots_start_y = wall;
            slots_start_z = watch_h + wall; // Empiezan sobre el hueco del reloj

            for (i = [0:pen_slots - 1]) {
                translate([
                    slots_start_x + i * (pen_slot_w + wall),
                    slots_start_y,
                    slots_start_z
                ]) {
                    cube([pen_slot_w, pen_section_inner_d, pen_organizer_h + 1]);
                }
            }
        }
    }
}