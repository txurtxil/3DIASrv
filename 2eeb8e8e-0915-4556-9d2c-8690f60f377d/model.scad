$fn = 24;

// Dimensiones generales del porta llaves (exteriores)
box_width = 10;   // Ancho total (eje X)
box_depth = 15;   // Profundidad total (eje Y)
box_height = 9;   // Alto total (eje Z)

// Dimensiones del hueco para la llave (interiores)
slot_width = 6;   // Ancho del hueco para la llave (eje X)
slot_height = 5;  // Alto del hueco para la llave (eje Z)
slot_depth = 10;  // Profundidad a la que se extiende el hueco dentro del objeto (eje Y)

// Diámetro del agujero para montaje (e.g., tornillo)
mount_hole_diameter = 3;

difference() {
    // Cuerpo principal del porta llaves
    cube([box_width, box_depth, box_height], center = true);

    // Recorte del hueco para la llave
    // El hueco se centra horizontal y verticalmente en la cara frontal.
    // Comienza en la cara frontal (-box_depth/2 en Y) y se extiende hacia adentro.
    translate([0, -box_depth / 2, 0]) {
        cube([slot_width, slot_depth, slot_height], center = true);
    }
    
    // Recorte del agujero de montaje
    // Se coloca en la parte superior sólida, centrado en X y se extiende a través de la profundidad.
    // La coordenada Z para el centro del agujero se calcula para posicionarlo en la mitad de la pared superior.
    translate([0, 0, (slot_height + box_height) / 4]) {
        cylinder(h = box_depth, d = mount_hole_diameter, center = true);
    }
}