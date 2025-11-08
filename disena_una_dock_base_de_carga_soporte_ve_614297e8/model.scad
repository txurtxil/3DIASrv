// OpenSCAD Dock para Google Pixel 10
// Experto en OpenSCAD para impresión 3D FDM
// Compatible con OpenSCAD 2021+

// ================================================================
// --- PARÁMETROS GLOBALES ---
// ================================================================
$fn = 24; // Resolución de las curvas

// --- Selección de la pieza a renderizar ---
// "support", "base", "assembly"
part_to_show = "assembly"; 

// --- Dimensiones del Teléfono (Google Pixel 10 estimado) ---
phone_height = 156.5; 
phone_width = 73.5; 
phone_thickness = 8.5;

// --- Dimensiones del Power Bank (Máximas) ---
powerbank_max_l = 148; // length (eje Y)
powerbank_max_w = 70;  // width (eje X)
powerbank_max_h = 15;  // height (eje Z)

// --- Parámetros de Diseño ---
wall_thickness = 2; // Espesor de pared mínimo
tolerance = 0.3;    // Holgura para el teléfono
joint_tolerance = 0.2; // Holgura para el encastre entre piezas
view_angle = 60;    // Ángulo de visión del soporte (grados respecto a la horizontal)

// --- Parámetros del Cable USB-C ---
cable_dia = 5;      // Diámetro del cable
connector_w = 12;   // Ancho del conector USB-C
connector_h = 7;    // Grosor del conector USB-C
connector_l = 25;   // Profundidad del conector en el soporte

// ================================================================
// --- MÓDULOS INTERNOS (no modificar) ---
// ================================================================

// Módulo para generar las hendiduras de los tacos de goma
module rubber_pad_hole() {
    cylinder(h = 1.5 + 0.1, d = 4, center = true);
}

// Módulo para generar el canal del cable
module cable_channel_path() {
    // Canal en la base
    hull() {
        translate([-powerbank_max_w/2 - 20, -5, 0]) 
            sphere(d = cable_dia + 1);
        translate([0, -25, 0]) 
            sphere(d = cable_dia + 1);
    }
    hull() {
        translate([0, -25, 0]) 
            sphere(d = cable_dia + 1);
        translate([0, -5, powerbank_max_h + wall_thickness + 5]) 
            sphere(d = cable_dia + 1);
    }
    // Canal en el soporte (antes de rotar)
    // El conector
    translate([0, phone_thickness/2 + tolerance/2, -connector_l/2 - 5])
        cube([connector_w, connector_h, connector_l], center=true);
    // El cable
    hull() {
        translate([0, phone_thickness/2 + tolerance/2, -30])
            sphere(d=cable_dia + 1);
        translate([0, phone_thickness/2 + tolerance/2, -50])
            sphere(d=cable_dia + 1);
    }
}

// ================================================================
// --- MÓDULO: SOPORTE SUPERIOR (Pieza 1) ---
// ================================================================
module support_part() {
    // Dimensiones internas del hueco para el teléfono
    phone_slot_w = phone_width + tolerance;
    phone_slot_h = phone_height; // La altura es abierta por arriba
    phone_slot_t = phone_thickness + tolerance;
    
    // Altura del labio inferior de sujección
    bottom_lip_h = 12;
    
    // Dimensiones del tenon de ensamble
    joint_tenon_w = 40;
    joint_tenon_d = 20;
    joint_tenon_h = 8;
    
    difference() {
        union() {
            // Cuerpo principal del soporte
            rotate([90 - view_angle, 0, 0]) 
            translate([0, 0, phone_slot_h/2 - bottom_lip_h])
            difference() {
                // Sólido exterior
                minkowski() {
                    cube([phone_slot_w, phone_slot_t, phone_slot_h], center=true);
                    sphere(d=wall_thickness*2);
                }
                // Vaciado interior para el teléfono
                translate([0, wall_thickness, 0])
                    cube([phone_slot_w, phone_slot_t + wall_thickness, phone_slot_h + wall_thickness*2], center=true);
            }
            
            // Tenon de ensamble en la base del soporte
            translate([0, -joint_tenon_d/2 - 1, -joint_tenon_h])
                cube([joint_tenon_w, joint_tenon_d, joint_tenon_h]);
            
            // Refuerzos triangulares
            hull() {
                translate([joint_tenon_w/2, 0, 0]) cylinder(h=1, d=wall_thickness*2);
                translate([joint_tenon_w/2, -15, -15]) rotate([0,90,0]) cylinder(h=1, d=wall_thickness*2);
            }
            hull() {
                translate([-joint_tenon_w/2, 0, 0]) cylinder(h=1, d=wall_thickness*2);
                translate([-joint_tenon_w/2, -15, -15]) rotate([0,90,0]) cylinder(h=1, d=wall_thickness*2);
            }

            // Pestañas de compresión superiores (2mm de flexión)
            tab_w = 20;
            tab_h = 10;
            tab_flex = 2;
            tab_offset_y = (phone_height/2 - tab_h) * sin(view_angle);
            tab_offset_z = (phone_height/2 - tab_h) * cos(view_angle);

            translate([phone_slot_w/2 + wall_thickness, tab_offset_y, tab_offset_z])
            rotate([90 - view_angle, 0, 0])
                cube([tab_flex, tab_w, tab_h]);
                
            translate([-phone_slot_w/2 - wall_thickness - tab_flex, tab_offset_y, tab_offset_z])
            rotate([90 - view_angle, 0, 0])
                cube([tab_flex, tab_w, tab_h]);
        }
        
        // --- Sustracciones ---

        // Recorte para carga inalámbrica (Qi)
        wireless_cutout_w = phone_width - 10;
        wireless_cutout_h = 100;
        rotate([90 - view_angle, 0, 0])
        translate([-wireless_cutout_w/2, -phone_slot_t/2 - wall_thickness*2, -20])
            cube([wireless_cutout_w, wall_thickness*2, wireless_cutout_h]);
        
        // Canal para el cable USB-C
        rotate([90 - view_angle, 0, 0])
            translate([0, 0, -phone_height/2 + bottom_lip_h + connector_l/2 - 2])
            cable_channel_path();
            
        // Recorte del labio inferior para no tapar la pantalla
        lip_cut_depth = (phone_slot_t/2 + wall_thickness) * cos(view_angle);
        lip_cut_height = (phone_slot_t/2 + wall_thickness) * sin(view_angle);
        translate([-(phone_slot_w/2 + wall_thickness), -lip_cut_depth, bottom_lip_h - lip_cut_height])
        rotate([view_angle-90,0,0])
            cube( [phone_slot_w+wall_thickness*2, phone_slot_t+wall_thickness*2, 40] );

        // Recorte superior para fácil acceso
        translate([0, 100, phone_height/2])
            rotate([90-view_angle, 0, 0])
            cylinder(h=200, d1=150, d2=100, center=true);
    }
}

// ================================================================
// --- MÓDULO: BASE INFERIOR (Pieza 2) ---
// ================================================================
module base_part() {
    base_w = powerbank_max_w + wall_thickness * 4;
    base_l = powerbank_max_l + wall_thickness * 4;
    base_h = powerbank_max_h + wall_thickness * 2;
    
    joint_mortise_w = 40 + joint_tolerance;
    joint_mortise_d = 20 + joint_tolerance;
    joint_mortise_h = 8 + 0.1;

    difference() {
        // Cuerpo principal de la base
        union() {
            // Bloque principal
            cube([base_w, base_l, base_h], center = true);
            
            // Patas antideslizantes
            foot_dia = 20;
            foot_h = 3;
            translate([ (base_w/2 - foot_dia/2),  (base_l/2 - foot_dia/2), -base_h/2 - foot_h/2]) cylinder(d=foot_dia, h=foot_h);
            translate([-(base_w/2 - foot_dia/2),  (base_l/2 - foot_dia/2), -base_h/2 - foot_h/2]) cylinder(d=foot_dia, h=foot_h);
            translate([ (base_w/2 - foot_dia/2), -(base_l/2 - foot_dia/2), -base_h/2 - foot_h/2]) cylinder(d=foot_dia, h=foot_h);
            translate([-(base_w/2 - foot_dia/2), -(base_l/2 - foot_dia/2), -base_h/2 - foot_h/2]) cylinder(d=foot_dia, h=foot_h);
        }
        
        // --- Sustracciones ---

        // Vaciado para el Power Bank
        translate([0, 0, wall_thickness/2])
            cube([powerbank_max_w + tolerance, powerbank_max_l + tolerance, powerbank_max_h + 0.1], center = true);
        
        // Abertura lateral para el puerto USB-C del power bank
        port_opening_w = 20;
        port_opening_h = 10;
        translate([base_w/2 - port_opening_w, -powerbank_max_l/2 + 20, 0])
            cube([port_opening_w*2, port_opening_h, port_opening_h], center=true);

        // Mortaja para el ensamble con el soporte
        translate([-(joint_mortise_w/2), -joint_mortise_d-1, base_h/2 - joint_mortise_h])
            cube([joint_mortise_w, joint_mortise_d, joint_mortise_h]);

        // Canal para el cable
        translate([0, 0, -base_h/2])
            cable_channel_path();

        // Hendiduras para los tacos de goma
        translate([ (base_w/2 - foot_dia/2),  (base_l/2 - foot_dia/2), -base_h/2 - 3]) rubber_pad_hole();
        translate([-(base_w/2 - foot_dia/2),  (base_l/2 - foot_dia/2), -base_h/2 - 3]) rubber_pad_hole();
        translate([ (base_w/2 - foot_dia/2), -(base_l/2 - foot_dia/2), -base_h/2 - 3]) rubber_pad_hole();
        translate([-(base_w/2 - foot_dia/2), -(base_l/2 - foot_dia/2), -base_h/2 - 3]) rubber_pad_hole();
    }
}

// ================================================================
// --- RENDERIZADO FINAL ---
// ================================================================

if (part_to_show == "support") {
    // Renderiza solo el soporte superior, centrado y en la base
    translate([0, 10.5, 8])
    rotate([0, 0, 180]) // Orientación para imprimir sin soportes en el tenon
        support_part();
} 
else if (part_to_show == "base") {
    // Renderiza solo la base, centrada y en el plano Z=0
    translate([0, 0, (powerbank_max_h + wall_thickness * 2)/2 + 3])
        base_part();
} 
else if (part_to_show == "assembly") {
    // Renderiza el ensamblaje completo
    // Base
    translate([0, 0, (powerbank_max_h + wall_thickness * 2)/2 + 3])
        color("lightblue") base_part();
    // Soporte
    translate([0, 0, (powerbank_max_h + wall_thickness * 2)])
        color("slategray") support_part();
}