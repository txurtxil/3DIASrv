// Constants
TOTAL_WIDTH = 30;         // Overall width at the base
TOTAL_DEPTH = 30;         // Overall depth at the base
TOTAL_HEIGHT = 35;        // Overall height
BASE_HEIGHT = 1.5;        // Height of the flat base plate
STRUCTURAL_THICKNESS = 2; // Minimum thickness for main structural elements (critical areas)
BAR_THICKNESS = 1.2;      // Minimum thickness for fine bars (lattice, railings)
PLATFORM_THICKNESS = 1.5; // Thickness of platforms
ANTENNA_DIAMETER = 1.2;   // Diameter of the antenna
ANTENNA_HEIGHT = 4;       // Height of the antenna

// Global variables for resolution
$fn = 24;

// Custom function to create an arc profile (half-ring segment for polygon extrusion)
// Returns a polygon suitable for linear_extrude. Assumes profile is in XZ plane.
function arc_profile(inner_r, outer_r, start_angle, end_angle, num_segments) =
    let (
        angles = [ for (i = [0:num_segments]) start_angle + (end_angle - start_angle) * i / num_segments ],
        outer_points = [ for (a = angles) [outer_r * cos(a), outer_r * sin(a)] ], // (X, Z)
        inner_points = [ for (a = reverse(angles)) [inner_r * cos(a), inner_r * sin(a)] ] // (X, Z)
    ) concat(outer_points, inner_points);

// Main Tower Assembly
module eiffel_tower() {
    // The entire object should be centered around (0,0,0).
    // The base's bottom face is at Z = -TOTAL_HEIGHT/2.
    // The base's center is at Z = -TOTAL_HEIGHT/2 + BASE_HEIGHT/2.
    translate([0, 0, -TOTAL_HEIGHT/2 + BASE_HEIGHT/2]) {
        base();
    }

    // All other components start from the top of the base.
    // Their local Z=0 corresponds to Z = -TOTAL_HEIGHT/2 + BASE_HEIGHT in global coordinates.
    translate([0, 0, -TOTAL_HEIGHT/2 + BASE_HEIGHT]) {
        tower_structure();
    }
}

// Base Module
module base() {
    cube([TOTAL_WIDTH, TOTAL_DEPTH, BASE_HEIGHT], center = true);
}

// Main tower structure (excluding the base)
module tower_structure() {
    // Define heights for platforms and sections relative to the top of the base
    P1_HEIGHT = 9;   // Height of the 1st platform
    P2_HEIGHT = 18;  // Height of the 2nd platform
    P3_HEIGHT = 26;  // Height of the 3rd platform
    TOWER_STRUCT_HEIGHT = TOTAL_HEIGHT - BASE_HEIGHT; // Total height for elements above base

    // Function to calculate tower width (side length) at a given height 'z'
    // This allows for tapering. The actual `leg_spread` will be slightly less than this.
    function get_structure_width_at_height(z) =
        TOTAL_WIDTH * (1 - z/TOWER_STRUCT_HEIGHT * 0.8) ; // Tapers to 20% of base width at top

    // Widths (spread of the legs' outer edges) at key heights
    LEG_SPREAD_BOTTOM = TOTAL_WIDTH - STRUCTURAL_THICKNESS * 2; // Initial spread of legs' outer edges
    LEG_SPREAD_P1 = get_structure_width_at_height(P1_HEIGHT) - STRUCTURAL_THICKNESS * 2;
    LEG_SPREAD_P2 = get_structure_width_at_height(P2_HEIGHT) - STRUCTURAL_THICKNESS * 2;
    LEG_SPREAD_P3 = get_structure_width_at_height(P3_HEIGHT) - STRUCTURAL_THICKNESS * 2;
    TOP_STRUCTURE_WIDTH = get_structure_width_at_height(TOWER_STRUCT_HEIGHT - ANTENNA_HEIGHT) - STRUCTURAL_THICKNESS * 2; // Width at the top of the main structure

    // Arched legs and main supports for the first section
    legs_and_arches(P1_HEIGHT, LEG_SPREAD_BOTTOM, LEG_SPREAD_P1);

    // Platforms with railings
    platform_with_railings(P1_HEIGHT, LEG_SPREAD_P1 + STRUCTURAL_THICKNESS * 2, PLATFORM_THICKNESS);
    platform_with_railings(P2_HEIGHT, LEG_SPREAD_P2 + STRUCTURAL_THICKNESS * 2, PLATFORM_THICKNESS);
    platform_with_railings(P3_HEIGHT, LEG_SPREAD_P3 + STRUCTURAL_THICKNESS * 2, PLATFORM_THICKNESS);

    // Lattice structure sections
    // Section 1: From above 1st platform to 2nd platform
    lattice_section(P1_HEIGHT + PLATFORM_THICKNESS/2, P2_HEIGHT, LEG_SPREAD_P1, LEG_SPREAD_P2);
    // Section 2: From above 2nd platform to 3rd platform
    lattice_section(P2_HEIGHT + PLATFORM_THICKNESS/2, P3_HEIGHT, LEG_SPREAD_P2, LEG_SPREAD_P3);
    // Section 3: From above 3rd platform to the base of the top finial
    lattice_section(P3_HEIGHT + PLATFORM_THICKNESS/2, TOWER_STRUCT_HEIGHT - ANTENNA_HEIGHT, LEG_SPREAD_P3, TOP_STRUCTURE_WIDTH);

    // Top finial and antenna
    translate([0, 0, TOWER_STRUCT_HEIGHT - ANTENNA_HEIGHT]) {
        top_finial_and_antenna(TOP_STRUCTURE_WIDTH);
    }
}

// Module for Arched Legs and Diagonal Reinforcements
module legs_and_arches(total_leg_height, bottom_spread, top_spread) {
    arch_bottom_z = 3;  // Z-height where the arch starts curving
    arch_top_z = 8;     // Z-height where the arch completes
    arch_thickness = STRUCTURAL_THICKNESS;

    for (i = [0, 90, 180, 270]) {
        rotate([0, 0, i]) {
            // Outer main leg, tapering inwards
            hull() {
                translate([bottom_spread/2, 0, 0])
                cube([arch_thickness, arch_thickness, BAR_THICKNESS], center = true);
                translate([top_spread/2, 0, total_leg_height - BAR_THICKNESS])
                cube([arch_thickness, arch_thickness, BAR_THICKNESS], center = true);
            }
            // Inner support for the arch, shorter and slightly less tapered
            hull() {
                translate([bottom_spread/2 - arch_thickness*2.5, 0, 0]) // Closer to center
                cube([arch_thickness, arch_thickness, BAR_THICKNESS], center = true);
                translate([top_spread/2 - arch_thickness*1.5, 0, arch_top_z - BAR_THICKNESS]) // Tapered to match upper structure
                cube([arch_thickness*0.8, arch_thickness, BAR_THICKNESS], center = true);
            }

            // Horizontal beam at arch_bottom_z, connecting outer and inner legs
            translate([bottom_spread/2 - arch_thickness*1.25, 0, arch_bottom_z]) {
                cube([arch_thickness*1.5, arch_thickness, BAR_THICKNESS], center = true);
            }
            // Horizontal beam at arch_top_z, connecting outer and inner legs (part of platform frame)
            translate([top_spread/2 - arch_thickness*0.75, 0, arch_top_z]) {
                cube([arch_thickness*0.7, arch_thickness, BAR_THICKNESS], center = true);
            }

            // The arch itself - a curved beam
            // Positioned to span from the inner leg at arch_top_z down to outer leg at arch_start_z roughly.
            // Using a custom arc_profile function for the shape.
            arch_span_x = (bottom_spread/2) - (bottom_spread/2 - arch_thickness*2.5); // X-distance between inner and outer leg at base
            arch_height_span = arch_top_z - arch_bottom_z;

            arch_outer_r = arch_span_x / 2 + arch_height_span * 0.6; // Adjusted radius for shape
            arch_inner_r = arch_outer_r - arch_thickness;

            translate([bottom_spread/2 - arch_thickness*2.5 + arch_thickness/2, 0, arch_bottom_z + arch_height_span/2]) {
                rotate([0, 90, 0]) { // Rotate to make arc curve in XZ plane, extruded along Y
                    linear_extrude(height = arch_thickness, center = true) {
                        polygon(arc_profile(arch_inner_r, arch_outer_r, 0, 90, $fn/2));
                    }
                }
            }
        }
    }

    // Diagonal reinforcements - simplified X-braces for lower section
    brace_outer_spread_bottom = bottom_spread - STRUCTURAL_THICKNESS;
    brace_outer_spread_top = top_spread - STRUCTURAL_THICKNESS;

    for (a = [45, 135, 225, 315]) { // Rotate for each diagonal plane (45, 135 degrees etc. from X-axis)
        rotate([0,0,a]) {
            // Lower brace (between 0 and arch_start_z)
            translate([0,0, arch_start_z/2]) {
                rotate([0, -atan2(arch_start_z, brace_outer_spread_bottom * sqrt(2)/2), 0]) { // Tilt for diagonal
                    cube([BAR_THICKNESS, BAR_THICKNESS, brace_outer_spread_bottom * sqrt(2)/2 * 1.1], center = true);
                }
            }
            // Upper brace (between arch_top_z and total_leg_height)
            translate([0,0, arch_top_z + (total_leg_height - arch_top_z)/2]) {
                rotate([0, -atan2(total_leg_height - arch_top_z, (brace_outer_spread_bottom + brace_outer_spread_top)/2 * sqrt(2)/2 ), 0]) {
                    cube([BAR_THICKNESS, BAR_THICKNESS, (brace_outer_spread_bottom + brace_outer_spread_top)/2 * sqrt(2)/2 * 1.1], center = true);
                }
            }
        }
    }
}

// Module for Platforms with Railings
module platform_with_railings(z_pos, width, height) {
    translate([0, 0, z_pos]) {
        // Platform plate
        cube([width, width, height], center = true);

        // Railings
        railing_height = 2.5; // Height of the railing posts above platform surface
        railing_post_thickness = BAR_THICKNESS;
        railing_bar_thickness = BAR_THICKNESS;

        // Top bar of railing
        translate([0, 0, height/2 + railing_height - railing_bar_thickness/2]) {
            difference() {
                cube([width + 2*railing_bar_thickness, width + 2*railing_bar_thickness, railing_bar_thickness], center = true);
                cube([width, width, railing_bar_thickness+0.1], center = true); // Cut out the inside
            }
        }

        // Bottom bar of railing
        translate([0, 0, height/2 + railing_bar_thickness/2]) {
            difference() {
                cube([width + 2*railing_bar_thickness, width + 2*railing_bar_thickness, railing_bar_thickness], center = true);
                cube([width, width, railing_bar_thickness+0.1], center = true);
            }
        }

        // Vertical posts for railings
        num_posts_per_side = 5; // Number of posts along one edge (including corners)
        post_spacing = width / (num_posts_per_side - 1);

        for (x_idx = [0 : num_posts_per_side-1]) {
            for (y_idx = [0 : num_posts_per_side-1]) {
                // Only place posts on the outer perimeter
                if (x_idx == 0 || x_idx == num_posts_per_side-1 || y_idx == 0 || y_idx == num_posts_per_side-1) {
                    translate([ -width/2 + x_idx * post_spacing, -width/2 + y_idx * post_spacing, height/2 + railing_height/2 - railing_bar_thickness/2 ]) {
                        cube([railing_post_thickness, railing_post_thickness, railing_height], center = true);
                    }
                }
            }
        }
    }
}

// Module for Lattice Structure sections
module lattice_section(start_z, end_z, start_width, end_width) {
    section_height = end_z - start_z;
    if (section_height <= BAR_THICKNESS * 2) return; // Prevent very short or negative height sections

    num_layers = floor(section_height / (BAR_THICKNESS * 4)); // Adjust for density
    if (num_layers < 1) num_layers = 1;
    layer_height = section_height / num_layers;

    for (layer = [0 : num_layers-1]) {
        current_z = start_z + layer * layer_height;
        // Interpolate width for current layer
        current_layer_width = start_width + (end_width - start_width) * (layer / num_layers);
        next_layer_width = start_width + (end_width - start_width) * ((layer + 1) / num_layers);

        // Horizontal frame bars at the bottom of each layer segment
        translate([0, 0, current_z]) {
            difference() {
                cube([current_layer_width, current_layer_width, BAR_THICKNESS], center = true);
                cube([current_layer_width - BAR_THICKNESS*2, current_layer_width - BAR_THICKNESS*2, BAR_THICKNESS+0.1], center = true);
            }
        }

        // Diagonal crosses for each of the four faces (X-pattern for triangular look)
        // Adjust for taper by taking average width for diagonal length calculation
        avg_layer_width = (current_layer_width + next_layer_width) / 2;
        diagonal_length = sqrt(pow(avg_layer_width, 2) + pow(layer_height, 2));

        // Front face (aligned with Y axis)
        translate([0, avg_layer_width/2, current_z + layer_height/2]) {
            rotate([0, -atan2(layer_height, avg_layer_width), 0]) { // Tilt for diagonal 1
                cube([BAR_THICKNESS, BAR_THICKNESS, diagonal_length * 1.05], center = true);
            }
            rotate([0, atan2(layer_height, avg_layer_width), 0]) { // Tilt for diagonal 2
                cube([BAR_THICKNESS, BAR_THICKNESS, diagonal_length * 1.05], center = true);
            }
        }
        // Right face (aligned with X axis)
        translate([avg_layer_width/2, 0, current_z + layer_height/2]) {
            rotate([atan2(layer_height, avg_layer_width), 0, 0]) { // Tilt for diagonal 1
                cube([BAR_THICKNESS, BAR_THICKNESS, diagonal_length * 1.05], center = true);
            }
            rotate([-atan2(layer_height, avg_layer_width), 0, 0]) { // Tilt for diagonal 2
                cube([BAR_THICKNESS, BAR_THICKNESS, diagonal_length * 1.05], center = true);
            }
        }
        // Back face (aligned with -Y axis)
        translate([0, -avg_layer_width/2, current_z + layer_height/2]) {
            rotate([0, atan2(layer_height, avg_layer_width), 0]) { // Tilt for diagonal 1
                cube([BAR_THICKNESS, BAR_THICKNESS, diagonal_length * 1.05], center = true);
            }
            rotate([0, -atan2(layer_height, avg_layer_width), 0]) { // Tilt for diagonal 2
                cube([BAR_THICKNESS, BAR_THICKNESS, diagonal_length * 1.05], center = true);
            }
        }
        // Left face (aligned with -X axis)
        translate([-avg_layer_width/2, 0, current_z + layer_height/2]) {
            rotate([-atan2(layer_height, avg_layer_width), 0, 0]) { // Tilt for diagonal 1
                cube([BAR_THICKNESS, BAR_THICKNESS, diagonal_length * 1.05], center = true);
            }
            rotate([atan2(layer_height, avg_layer_width), 0, 0]) { // Tilt for diagonal 2
                cube([BAR_THICKNESS, BAR_THICKNESS, diagonal_length * 1.05], center = true);
            }
        }
    }
}

// Module for Top Finial and Antenna
module top_finial_and_antenna(base_width) {
    finial_height = 2; // Height of the structural part of the finial
    finial_top_width = base_width * 0.5; // Top width of the finial structure

    // Finial base (small platform)
    cube([base_width, base_width, BAR_THICKNESS], center = true);

    // Tapered finial structure
    translate([0, 0, BAR_THICKNESS + finial_height/2]) {
        hull() {
            cube([base_width * 0.8, base_width * 0.8, BAR_THICKNESS], center = true);
            translate([0, 0, finial_height])
            cube([finial_top_width, finial_top_width, BAR_THICKNESS], center = true);
        }
    }

    // Antenna
    translate([0, 0, BAR_THICKNESS + finial_height + ANTENNA_HEIGHT/2]) {
        cylinder(h = ANTENNA_HEIGHT, d = ANTENNA_DIAMETER, center = true);
    }
}

// Render the entire tower
eiffel_tower();