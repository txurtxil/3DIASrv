// Global parameters for OpenSCAD rendering
$fn = 24;

// --- Hook Dimensions ---
// Base Plate Dimensions (X, Y, Z)
base_width = 60;  // X-axis dimension (along the wall)
base_height = 40; // Y-axis dimension (up/down the wall)
base_thickness = 5; // Z-axis dimension (protruding from the wall). Must be >= 2mm.

// Arm Dimensions
arm_projection_straight = 30; // Length of the straight part of the arm (along Z)
arm_cross_section_width = 15; // Width of the arm (along X). Must be >= 2mm.
arm_cross_section_depth = 10; // Depth/thickness of the arm (along Y). Must be >= 2mm.

// Hook Curve Details
hook_tip_length = 20;  // Length of the final upward pointing tip (along Y)
hook_tip_radius = 5;   // Radius for rounding the very tip of the hook

// Screw Hole Parameters
screw_hole_diameter = 4.2; // For M4 screws (e.g., 4.0mm screw + 0.2mm tolerance)
screw_hole_offset_x = 20;  // Distance from center along X for screw holes
screw_hole_offset_y = 0;   // No offset along Y if only 2 holes centered on Y axis

// Fillet and Rounding Parameters
base_arm_transition_radius = 8; // Fillet radius for the connection between base and arm

// --- Main Hook Assembly ---
// Centered at (0,0,0): The geometric center of the base plate is at (0,0,0).
// The hook arm extends from the front face of the base.
union() {
    // Wall Plate - centered at (0,0,0)
    difference() {
        // Main base plate body
        cube([base_width, base_height, base_thickness], center = true);

        // Screw holes - positioned in the middle of the base plate in Z
        for (pos = [-1, 1]) {
            translate([pos * screw_hole_offset_x, screw_hole_offset_y, 0]) {
                cylinder(h = base_thickness + 1, d = screw_hole_diameter, center = true);
            }
        }
    }

    // Hook Arm - constructed using a series of hulls for robustness and smooth transitions
    // This design creates a strong, solid 'J' shape for the hook.

    // Part 1: Hull between the base plate and the start of the straight arm section
    // This creates a smooth, strong fillet at the base of the hook.
    hull() {
        // Sphere representing the connection point at the base, creating a rounded joint
        translate([0, 0, base_thickness / 2])
            sphere(r = base_arm_transition_radius);

        // Cube representing the end of the straight section of the arm
        // This cube defines the cross-section and extends the arm forward.
        translate([0, 0, base_thickness / 2 + arm_projection_straight])
            cube([arm_cross_section_width, arm_cross_section_depth, base_arm_transition_radius * 2], center = true);
    }

    // Part 2: Hull for the curved part of the arm and the tip
    // This connects the straight part to the upward-curling tip.
    hull() {
        // Cube at the end of the straight section (repeated for hulling with the next shape)
        translate([0, 0, base_thickness / 2 + arm_projection_straight])
            cube([arm_cross_section_width, arm_cross_section_depth, base_arm_transition_radius * 2], center = true);

        // Sphere representing the tip of the hook, where it curls upwards.
        // Positioned with its center at the highest point of the curl.
        translate([0, hook_tip_length, base_thickness / 2 + arm_projection_straight - hook_tip_length])
            sphere(r = hook_tip_radius + arm_cross_section_depth / 2); // Sphere for a smooth, rounded tip
    }
}