// -- Parámetros Clave --
// Dimensiones estimadas para Google Pixel 10 con funda delgada
phone_width = 80;       // Ancho del teléfono en mm
phone_thickness = 11;   // Grosor del teléfono en mm

// Propiedades del soporte
stand_width = phone_width + 10;  // Ancho total, 5mm de margen por lado
wall_thickness = 2.0;            // Regla 3: Grosor mínimo de pared
base_depth = 80;                 // Profundidad de la base para estabilidad
back_height = 100;               // Altura del respaldo
lip_height = 15;                 // Altura del labio frontal para sujetar el móvil
view_angle = 70;                 // Ángulo de inclinación (grados desde la horizontal)

// Hueco para conector USB-C
usb_cutout_width = 25;
usb_cutout_height = 10;

// -- Calidad del Modelo --
$fn = 24; // Regla 4: Resolución para curvas

// -- Inicio del Modelo --
// El 'translate' exterior centra el objeto final en el origen (Regla 2)
translate([ -base_depth / 2, 0, -back_height / 2 ]) {

    // Usamos difference() para sustraer volúmenes de un sólido base
    difference() {

        // 1. CUERPO SÓLIDO PRINCIPAL //
        // Se crea un perfil 2D en el plano X-Z y se extruye en Y para formar el cuerpo
        linear_extrude(height = stand_width, center = true) {
            polygon([
                [0, 0],                                                   // Punto inferior-frontal
                [base_depth, 0],                                          // Punto inferior-trasero
                [base_depth - back_height / tan(view_angle), back_height],  // Punto superior-trasero
                [0, lip_height]                                           // Punto superior del labio frontal
            ]);
        }

        // 2. HUECO PARA EL SMARTPHONE //
        // Un cubo largo, rotado al ángulo correcto, que se sustrae del cuerpo principal
        // Se mueve 'wall_thickness' hacia adentro para crear las paredes
        translate([wall_thickness, 0, wall_thickness]) {
            rotate([-(90 - view_angle), 0, 0]) {
                // Usamos un cubo más grande de lo necesario para asegurar un corte limpio
                // Se centra en sus propios ejes para facilitar la rotación y posicionamiento
                translate([phone_thickness / 2, 0, back_height])
                    cube([phone_thickness, phone_width, back_height * 2], center = true);
            }
        }

        // 3. HUECO PARA EL CABLE USB-C //
        // Un cubo que corta la parte inferior del labio frontal
        // Se posiciona al frente y abajo, centrado en el ancho (eje Y)
        translate([0, 0, wall_thickness + (usb_cutout_height / 2)]) {
             // El cubo es más profundo (eje X) de lo necesario para asegurar el corte a través del labio inclinado
            cube([35, usb_cutout_width, usb_cutout_height], center = true);
        }
    }
}