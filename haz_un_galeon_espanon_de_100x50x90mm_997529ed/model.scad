// OpenSCAD Galeón Español para Impresión 3D FDM
// Dimensiones Objetivo: 100x50x90mm
// Centrado en (0,0,0)
// Mínimo grosor de pared: 2mm

$fn = 24;

// --- Parámetros Globales ---
ship_length = 85;   // Longitud del casco principal
ship_width = 40;    // Ancho del casco principal
deck_level = 8;     // Nivel de la cubierta principal en Z
min_wall = 2;

// --- Módulo Principal ---
// Centra el galeón completo en el origen
// Centro calculado X: -8, Z: 31
translate([-8, 0, -31]) {
    galeon();
}

// --- Ensamblaje del Galeón ---
module galeon() {
    union() {
        casco();
        superestructura();
        mastiles_y_velas();
        detalles();
    }
}

// --- Casco ---
module casco() {
    difference() {
        // Forma base del casco usando la función hull() para suavizar
        hull() {
            // Popa (Stern) - Ancha y alta
            translate([ship_length * 0.5, 0, 0])
                cylinder(h = 22, d1 = ship_width, d2 = ship_width * 0.9, center = true);

            // Centro
            translate([0, 0, 0])
                cylinder(h = 18, d = ship_width, center = true);
            
            // Proa (Bow) - Estrecha y elevada
            translate([-ship_length * 0.5, 0, -5])
                cylinder(h = 14, d1 = ship_width * 0.8, d2 = ship_width * 0.1, center = true);
        }
        // Corte superior para crear una cubierta plana y sólida
        translate([0, 0, deck_level + 25])
            cube([ship_length * 1.2, ship_width * 1.2, 50], center = true);
    }
}

// --- Superestructura (Castillos de Proa y Popa) ---
module superestructura() {
    // Castillo de Popa (Sterncastle) - Múltiples niveles en la parte trasera
    translate([ship_length * 0.35, 0, deck_level + 4]) {
        // Nivel 1
        cube([ship_length * 0.4, ship_width * 0.9, 8], center = true);
        // Nivel 2
        translate([0, 0, 6])
            cube([ship_length * 0.3, ship_width * 0.85, 8], center = true);
        // Barandilla Popa
        difference() {
            translate([0, 0, 12])
                cube([ship_length * 0.3, ship_width * 0.85, 4], center = true);
            translate([0, 0, 12])
                cube([ship_length * 0.3 - min_wall*2, ship_width * 0.85 - min_wall*2, 5], center = true);
        }
    }
    
    // Castillo de Proa (Forecastle) - Cubierta elevada en la parte delantera
    translate([-ship_length * 0.35, 0, deck_level + 4]) {
        deck_l = ship_length * 0.4;
        deck_w = ship_width * 0.8;
        hull() {
             cube([deck_l, deck_w, 8], center = true);
             translate([-deck_l/2, 0, 0]) cylinder(h=8, d=deck_w, center=true);
        }
        // Barandilla Proa
        difference() {
             hull() {
                translate([0, 0, 6]) cube([deck_l, deck_w, 4], center = true);
                translate([-deck_l/2, 0, 6]) cylinder(h=4, d=deck_w, center=true);
             }
             hull() {
                translate([0, 0, 6]) cube([deck_l - min_wall*2, deck_w-min_wall*2, 5], center=true);
                translate([-deck_l/2, 0, 6]) cylinder(h=5, d=deck_w-min_wall*2, center=true);
             }
        }
    }
}

// --- Mástiles, Vergas y Velas ---
module mastiles_y_velas() {
    // Bauprés (Bowsprit) - Palo que sobresale de la proa
    translate([-ship_length * 0.45, 0, 10])
        rotate([0, -20, 0])
            cylinder(h = 45, d = 4, center = true);

    // Mástil de Trinquete (Foremast) - Delantero
    translate([-ship_length * 0.25, 0, 35])
        mastil_con_velas(altura=50, vela_ancho=30, vela_alto=25);

    // Mástil Mayor (Mainmast) - Central y más alto
    translate([ship_length * 0.1, 0, 47])
        mastil_con_velas(altura=65, vela_ancho=38, vela_alto=30, num_velas=2);
        
    // Mástil de Mesana (Mizzenmast) - Trasero
    translate([ship_length * 0.4, 0, 32])
        rotate([0, 5, 0]) // Ligeramente inclinado hacia popa
            mastil_con_vela_latina(altura=40, vela_largo=30, vela_alto=25);
}

// --- Módulo para Mástil con Velas Cuadradas ---
module mastil_con_velas(altura, vela_ancho, vela_alto, num_velas=1) {
    // Mástil
    cylinder(h = altura, d = 4.5, center = true);
    
    // Vergas (palos horizontales) y Velas
    for (i = [1:num_velas]) {
        translate([0, 0, altura/4 - (i-1)*(vela_alto*0.9)]) {
            // Verga
            translate([0, 0, vela_alto/2])
                rotate([0, 0, 90])
                    cylinder(h = vela_ancho * 1.1, d = 3, center = true);
            // Vela
            cube([vela_ancho, min_wall, vela_alto], center = true);
        }
    }
}

// --- Módulo para Mástil con Vela Latina (Triangular) ---
module mastil_con_vela_latina(altura, vela_largo, vela_alto) {
    // Mástil
    cylinder(h = altura, d = 4, center = true);
    
    // Verga inclinada (Entena)
    translate([0,0,-5])
    rotate([0, 0, 90])
    rotate([45, 0, 0])
        cylinder(h = vela_largo * 1.4, d = 3, center = true);
        
    // Vela Latina
    translate([-2, -min_wall/2, -altura/2 + 2])
        linear_extrude(height = min_wall)
            polygon(points=[[0,0], [vela_largo, 0], [5, vela_alto]]);
}

// --- Detalles Adicionales ---
module detalles() {
    // Timón (Rudder)
    translate([ship_length/2 + 1, 0, -8])
        cube([min_wall, 10, 18], center = true);
    
    // Cañones (Cannons)
    for (y_pos = [-1, 1]) { // Babor y Estribor (izquierda y derecha)
        mirror([0, y_pos, 0]) {
            for (i = [0:3]) {
                translate([ship_length * 0.2 - i * 15, ship_width/2, 3])
                    rotate([0,90,0])
                        cylinder(h = 6, d = 3, center = true);
            }
        }
    }
}