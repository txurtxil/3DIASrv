// Global settings for curves
$fn = 24;

// Key holder main body dimensions
tag_length = 50; // Overall length of the key holder
tag_width = 20;  // Overall width of the key holder
tag_thickness = 4; // Overall thickness (depth) of the key holder, ensures > 2mm wall

// Keyring hole dimensions
hole_diameter = 5; // Diameter of the hole for the keyring
hole_radius = hole_diameter / 2;
hole_offset_from_end = 5; // Distance from the end of the tag to the center of the hole

// Main key holder object centered at (0,0,0)
difference() {
    // Main rectangular body of the key holder
    cube([tag_length, tag_width, tag_thickness], center = true);

    // Keyring hole cutout
    // Positioned near one end (positive X side) and centered on Y and Z axis
    translate([
        (tag_length / 2) - hole_offset_from_end, // X position: from the end towards the center
        0,                                        // Y position: centered
        0                                         // Z position: centered
    ])
    cylinder(r = hole_radius, h = tag_thickness + 0.1, center = true); // Z-height slightly extended for clean cut
}