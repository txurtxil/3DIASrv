// Set resolution for curves (though not applicable to a perfect cube)
$fn = 24;

difference() {
    // Outer cube: 10x10x10mm, centered at (0,0,0)
    cube([10, 10, 10], center = true);

    // Inner cube: 6x6x6mm (10mm - 2*2mm wall thickness), centered at (0,0,0)
    // This creates 2mm minimum wall thickness on all sides
    cube([6, 6, 6], center = true);
}