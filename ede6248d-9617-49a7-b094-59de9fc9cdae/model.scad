// Global Parameters
base_width = 80; // Overall width and depth of the tower base
total_height = 95; // Total height of the tower
wall_thickness = 2; // Minimum wall thickness for all structural elements
$fn = 24; // Number of facets for smooth curves (cylinders, spheres, arcs)

// Platform Heights (relative to total_height, defining where platforms start)
level1_z = total_height * 0.25; // Z-coordinate for the base of the first (bottom) platform
level2_z = total_height * 0.55; // Z-coordinate for the base of the second (middle) platform
level3_z = total_height * 0.80; // Z-coordinate for the base of the third (top) platform

// Platform Widths (relative to base_width, defining the size of platforms and leg taper)
platform1_top_width = base_width * 0.50; // Width of the first platform
platform2_top_width = base_width * 0.25; // Width of the second platform
platform3_top_width = base_width * 0.10; // Width of the third platform
dome_base_width = base_width * 0.05; // Width of the tower structure just before the dome/spire

platform_thickness = 2.5; // Thickness of each horizontal platform layer

// Module to create a single tapered beam segment for a main leg.
// 'outer_coords_start' = [x,y,z] for the outermost corner of the tower profile at the start of the beam.
// 'outer_coords_end' = [x,y,z] for the outermost corner of the tower profile at the end of the beam.
module make_leg_beam_segment(outer_coords_start, outer_coords_end) {
    hull() {
        // Defines the square cross-section at the start of the beam
        translate([outer_coords_start[0] - wall_thickness, outer_coords_start[1] - wall_thickness, outer_coords_start[2]])
            cube([wall_thickness, wall_thickness, 0.01]); // 0.01 height to make it a point for hull

        // Defines the square cross-section at the end of the beam
        translate([outer_coords_end[0] - wall_thickness, outer_coords_end[1] - wall_thickness, outer_coords_end[2]])
            cube([wall_thickness, wall_thickness, 0.01]);
    }
}

// Module to create a simplified arch structure
// 'total_span' is the overall width of the arch beam
// 'arch_inner_radius' is the radius of the cutout for the arch opening
// 'arch_height_val' is the vertical height of the arch opening
// 'thickness' is the depth of the arch beam
module create_simple_arch_beam(total_span, arch_inner_radius, arch_height_val, thickness) {
    difference() {
        // Outer arch form (a solid block + half-cylinder top)
        union() {
            // Rectangular base of the arch beam
            translate([-total_span/2, -thickness/2, 0])
                cube([total_span, thickness, arch_height_val + thickness/2], center=false);
            // Rounded top part of the arch beam (a segment of a cylinder)
            translate([0, 0, arch_height_val])
                rotate([90,0,0]) // Rotate to make it stand upright
                cylinder(r=total_span/2, h=thickness, center=true);
        }
        // Inner cutout for the arch opening (a larger cylinder to ensure full cutout)
        translate([0, 0, arch_height_val])
            rotate([90,0,0])
            cylinder(r=arch_inner_radius, h=thickness*2, center=true);
    }
}

// Module to create the characteristic triangular lattice structure for a section
// 'z_start_section', 'z_end_section': Z-coordinates defining the section's height
// 'outer_width_start_section', 'outer_width_end_section': Widths defining the taper of the section
// 'num_levels': Number of horizontal segments within this section
module make_grid_lattice(z_start_section, z_end_section, outer_width_start_section, outer_width_end_section, num_levels) {
    level_height = (z_end_section - z_start_section) / num_levels;

    for (i = [0:num_levels]) {
        current_z = z_start_section + i * level_height;
        current_outer_width = outer_width_start_section - (outer_width_start_section - outer_width_end_section) * (i / num_levels);

        // Horizontal beams at each lattice level
        // These 4 beams connect the main vertical legs along the X and Y axes
        for (j = [0:3]) {
            rotate([0, 0, j*90]) {
                // Creates a beam of 'wall_thickness' height, spanning between the inner edges of the main legs
                translate([0, current_outer_width/2 - wall_thickness/2, current_z])
                    cube([current_outer_width - wall_thickness * 2, wall_thickness, wall_thickness], center=true);
            }
        }

        // Diagonal beams (creating the 'X' or triangular pattern between horizontal levels)
        if (i < num_levels) { // Diagonals are created for each segment *between* horizontal levels
            next_z = z_start_section + (i + 1) * level_height;
            next_outer_width = outer_width_start_section - (outer_outer_width_start_section - outer_width_end_section) * ((i + 1) / num_levels);

            for (j = [0:3]) {
                rotate([0, 0, j*90]) {
                    // Diagonal 1: Connects the outer-front-right corner of the current level to the outer-back-left corner of the next level
                    hull() {
                        translate([current_outer_width/2 - wall_thickness, current_outer_width/2 - wall_thickness, current_z])
                            cube([wall_thickness, wall_thickness, 0.01]);
                        translate([next_outer_width/2 - wall_thickness, -(next_outer_width/2 - wall_thickness), next_z])
                            cube([wall_thickness, wall_thickness, 0.01]);
                    }
                    // Diagonal 2: Connects the outer-front-left corner of the current level to the outer-back-right corner of the next level
                    hull() {
                        translate([current_outer_width/2 - wall_thickness, -(current_outer_width/2 - wall_thickness), current_z])
                            cube([wall_thickness, wall_thickness, 0.01]);
                        translate([next_outer_width/2 - wall_thickness, next_outer_width/2 - wall_thickness, next_z])
                            cube([wall_thickness, wall_thickness, 0.01]);
                    }
                }
            }
        }
    }
}

// Main Tower Assembly
union() {
    // SECTION: Patas (Legs)
    // The tower's structure consists of 4 main tapering legs at its corners.
    // Each leg is built from segments between platforms.
    for (i = [0:3]) { // Rotate for each of the 4 quadrants (0, 90, 180, 270 degrees)
        rotate([0, 0, i*90]) {
            // Define the outer corner points for a single quadrant (+X, +Y) at each level
            p_base_outer = [base_width/2, base_width/2, 0];
            p1_outer = [platform1_top_width/2, platform1_top_width/2, level1_z - platform_thickness];
            p2_outer = [platform2_top_width/2, platform2_top_width/2, level2_z - platform_thickness];
            p3_outer = [platform3_top_width/2, platform3_top_width/2, level3_z - platform_thickness];
            p_dome_base_outer = [dome_base_width/2, dome_base_width/2, total_height - platform_thickness];

            // Construct each segment of the main leg using 'make_leg_beam_segment'
            make_leg_beam_segment(p_base_outer, p1_outer);
            make_leg_beam_segment(p1_outer, p2_outer);
            make_leg_beam_segment(p2_outer, p3_outer);
            make_leg_beam_segment(p3_outer, p_dome_base_outer);
        }
    }

    // SECTION: Plataformas (Platforms)
    // Create the three horizontal platforms that connect the legs and provide structural stability.
    // These platforms extend to cover the outermost edges of the main legs.

    // Bottom Platform (Level 1)
    translate([0, 0, level1_z - platform_thickness])
        cube([platform1_top_width + wall_thickness*2, platform1_top_width + wall_thickness*2, platform_thickness], center=true);

    // Middle Platform (Level 2)
    translate([0, 0, level2_z - platform_thickness])
        cube([platform2_top_width + wall_thickness*2, platform2_top_width + wall_thickness*2, platform_thickness], center=true);

    // Top Platform (Level 3)
    translate([0, 0, level3_z - platform_thickness])
        cube([platform3_top_width + wall_thickness*2, platform3_top_width + wall_thickness*2, platform_thickness], center=true);

    // SECTION: Arcos (Arches)
    // Four large arches at the base, connecting the main legs.
    // These arches have a curved top and a straight bottom section.
    arch_total_span = base_width - wall_thickness; // The overall span for the arch (from outer edge of one leg to the outer edge of the other, minus wall_thickness)
    arch_height_main = level1_z * 0.75; // Max height of the arch opening
    arch_inner_radius = (arch_total_span/2) - wall_thickness/2; // Radius for the cutout, ensuring wall thickness

    for (i = [0:3]) {
        rotate([0, 0, i*90]) {
            // Position the arch: It spans across the X-axis in its own rotated frame,
            // with its back edge aligned with the positive Y-axis's outer edge.
            translate([0, base_width/2 - arch_total_span - wall_thickness/2, 0])
                create_simple_arch_beam(arch_total_span, arch_inner_radius, arch_height_main, wall_thickness);
        }
    }

    // SECTION: Celosía (Lattice)
    // The characteristic triangular lattice filling the spaces between the main legs.
    // Applied to each section between platforms, tapering appropriately.

    // Lattice for the section from base (Z=0) to the first platform
    make_grid_lattice(0, level1_z - platform_thickness, base_width, platform1_top_width, 5); // 5 levels of lattice

    // Lattice for the section from the first platform to the second platform
    make_grid_lattice(level1_z, level2_z - platform_thickness, platform1_top_width, platform2_top_width, 4); // 4 levels

    // Lattice for the section from the second platform to the third platform
    make_grid_lattice(level2_z, level3_z - platform_thickness, platform2_top_width, platform3_top_width, 3); // 3 levels

    // Lattice for the section from the third platform to the dome base
    make_grid_lattice(level3_z, total_height - platform_thickness, platform3_top_width, dome_base_width, 2); // 2 levels

    // SECTION: Remate (Top/Dome)
    // The spire and dome at the very top of the tower.

    spire_start_z = total_height - platform_thickness; // The Z-coordinate where the spire begins
    spire_height_section = total_height - spire_start_z; // Total height allocated for the spire

    // Main spire cone (tapering upwards)
    translate([0, 0, spire_start_z])
        cylinder(r1=dome_base_width/2, r2=wall_thickness/2, h=spire_height_section * 0.75, center=false);

    // Small decorative sphere at the spire's tip
    translate([0, 0, spire_start_z + spire_height_section * 0.75])
        sphere(r=wall_thickness * 0.75);

    // Final tiny pointed cone at the very top
    translate([0, 0, spire_start_z + spire_height_section * 0.75 + wall_thickness * 0.75])
        cylinder(r1=wall_thickness/2, r2=0, h=spire_height_section * 0.25, center=false);
}