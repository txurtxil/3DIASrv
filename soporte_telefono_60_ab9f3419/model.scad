// Dimensiones del soporte
wall_thickness = 2; // Grosor mínimo de la pared
base_width = 80;    // Ancho de la base
base_depth = 100;   // Profundidad de la base
support_height = 120; // Altura vertical del soporte trasero desde la base
angle = 60;         // Ángulo de inclinación del soporte trasero respecto a la base (grados)
lip_height = 10;    // Altura del labio frontal
lip_depth = 15;     // Profundidad del labio frontal

// Dimensiones de la ranura para cable/teléfono
slot_width = 15;    // Ancho de la ranura
slot_depth = lip_depth + 5; // Profundidad de la ranura (corta el labio y parte de la base)
slot_height = wall_thickness + 3; // Altura de la ranura para permitir el paso de cables o el borde del teléfono

// Ajustes generales para curvas
$fn = 24;

// Estructura principal del soporte
difference() {
  union() {
    // Base principal del soporte
    // Centrada en X, Y. La parte inferior está en Z=0.
    translate([0, 0, wall_thickness / 2]) {
      cube([base_width, base_depth, wall_thickness], center = true);
    }

    // Placa de soporte trasera inclinada 60 grados
    // El punto de pivote para la rotación es:
    // X=0 (centrado), Y=-base_depth/2 (borde trasero de la base), Z=wall_thickness (parte superior de la base)
    translate([0, -base_depth / 2, wall_thickness]) {
      // Calcula la longitud de la placa a lo largo de la pendiente para lograr la altura vertical deseada
      slanted_length = support_height / sin(angle);
      // Rota alrededor del eje X. Ángulo negativo para inclinar hacia atrás.
      rotate([-angle, 0, 0]) {
        // Posiciona el cubo: centrado en X, su cara "trasera" (a lo largo de Y=0) en el pivote,
        // y su cara "inferior" (a lo largo de Z=0) en el pivote.
        // Dimensiones del cubo: [ancho, grosor, largo]
        translate([0, wall_thickness / 2, slanted_length / 2]) {
          cube([base_width, wall_thickness, slanted_length], center = true);
        }
      }
    }

    // Borde frontal (labio) para sujetar el teléfono
    // Posición: Centrado en X. Su cara trasera en Y = base_depth/2 - lip_depth.
    // Su cara inferior en Z = wall_thickness (encima de la base).
    translate([0, base_depth / 2 - lip_depth / 2, wall_thickness + lip_height / 2]) {
      cube([base_width, lip_depth, lip_height], center = true);
    }
  } // Fin union de las partes principales

  // Ranura para cable de carga o borde del teléfono
  // Posición: Centrada en X. En la parte delantera de la base/labio. Su parte inferior está en Z=0.
  translate([0, base_depth / 2 - slot_depth / 2, slot_height / 2]) {
    cube([slot_width, slot_depth, slot_height], center = true);
  }
} // Fin difference (cuerpo principal menos la ranura)