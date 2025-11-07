// Global settings for curved surfaces
$fn = 24;

// --- Box Dimensions (External) ---
L = 60; // Length in mm
W = 40; // Width in mm
H = 30; // Total Height in mm (base + lid top thickness)

// --- Wall Thickness ---
T = 2; // Wall and bottom thickness in mm (minimum 2mm as per rules)

// --- Lid Parameters ---
LID_TOP_H = 3; // Height of the flat top part of the lid in mm
LID_FIT_TOLERANCE = 0.2; // Total tolerance for the lid's lip to fit inside the base in mm.
                         // This means 0.1mm gap on each side (L and W).
LID_LIP_H = 8; // Height of the lip that extends from the lid into the box base in mm

// --- Derived Dimensions ---
// Height of the box base part (total height minus lid top height)
BASE_H = H - LID_TOP_H;

// --- Module: Box Base ---
// Generates the main body of the box. When called without translation,
// its geometric center will be at (0,0,0).
module box_base() {
    difference() {
        // Outer dimensions of the box base
        cube([L, W, BASE_H], center=true);

        // Inner void to create walls and a solid bottom of thickness T.
        // The inner cube is moved up by T/2 so that its bottom face is T mm
        // above the bottom face of the outer cube.
        translate([0, 0, T/2]) {
            cube([L - 2*T, W - 2*T, BASE_H - T], center=true);
        }
    }
}

// --- Module: Box Lid ---
// Generates the lid, designed to fit onto the box_base.
// When called without translation, its geometric center will be at (0,0,0).
module box_lid() {
    union() {
        // Top flat part of the lid
        cube([L, W, LID_TOP_H], center=true);

        // Lip that fits inside the box base's walls.
        // Its length and width are reduced by 2*T (for box walls)
        // and LID_FIT_TOLERANCE (for fit clearance).
        // Its Z position is adjusted so its top surface aligns with the
        // bottom surface of the LID_TOP_H part.
        translate([0, 0, -LID_TOP_H/2 - LID_LIP_H/2]) {
            cube([L - 2*T - LID_FIT_TOLERANCE, W - 2*T - LID_FIT_TOLERANCE, LID_LIP_H], center=true);
        }
    }
}

// --- Main Render Section ---
// Calls the modules to display the box base and lid.
// They are translated for clear visualization, showing the lid above the base.

// Display the box base. It's translated downwards so its bottom surface
// rests on the Z=0 plane, which is typical for 3D printing.
translate([0, 0, -BASE_H/2]) {
    box_base();
}

// Display the box lid. It's translated upwards to sit above the base
// with a small gap (5mm) for better visualization of the two separate parts.
// The lid's center is positioned at the top of the base (BASE_H) + half its own height (LID_TOP_H/2) + gap.
translate([0, 0, BASE_H + LID_TOP_H/2 + 5]) {
    box_lid();
}