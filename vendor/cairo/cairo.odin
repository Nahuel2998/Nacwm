package cairo

import "core:c"
import X "../../vendor/x11/xlib"

surface_t :: struct{}
cairo_t   :: struct{}

foreign import "system:cairo"
@(default_calling_convention="c", link_prefix="cairo_")
foreign cairo {
    // Creates an Xlib surface that draws to the given drawable. The way that colors are represented in the drawable is specified by the provided visual.
    // Note: If drawable is a Window, then the function cairo_xlib_surface_set_size() must be called whenever the size of the window changes.
    // When drawable is a Window containing child windows then drawing to the created surface will be clipped by those child windows. When the created surface is used as a source, the contents of the children will be included.
    xlib_surface_create :: proc(
        dpy      : ^X.Display,
        drawable :  X.Drawable,
        visual   : ^X.Visual,
        width, height : c.int,
    ) -> ^surface_t ---
    // Decreases the reference count on surface by one. If the result is zero, then surface and all associated resources are freed. See cairo_surface_reference().
    surface_destroy :: proc(
        surface : ^surface_t,
    ) ---
    // Do any pending drawing for the surface and also restore any temporary modifications cairo has made to the surface's state. This function must be called before switching from drawing on the surface with cairo to drawing on it directly with native APIs, or accessing its memory outside of Cairo. If the surface doesn't support direct access, then this function does nothing.
    surface_flush :: proc(
        surface : ^surface_t,
    ) ---
    // Creates a new cairo_t with all graphics state parameters set to default values and with target as a target surface. The target surface should be constructed with a backend-specific function such as cairo_image_surface_create() (or any other cairo_backend_surface_create() variant).
    // This function references target, so you can immediately call cairo_surface_destroy() on it if you don't need to maintain a separate reference to it.
    create :: proc(
        target : ^surface_t,
    ) -> ^cairo_t ---
    // Decreases the reference count on cr by one. If the result is zero, then cr and all associated resources are freed. See cairo_reference().
    destroy :: proc(
        cr : ^cairo_t,
    ) ---
    // Begin a new sub-path. After this call the current point will be (x, y).
    move_to :: proc(
        cr   : ^cairo_t,
        x, y : c.double,
    ) ---
    // Sets the source pattern within cr to an opaque color. This opaque color will then be used for any subsequent drawing operation until a new source pattern is set.
    // The color components are floating point numbers in the range 0 to 1. If the values passed in are outside that range, they will be clamped.
    // The default source pattern is opaque black, (that is, it is equivalent to cairo_set_source_rgb(cr, 0.0, 0.0, 0.0)).
    set_source_rgb :: proc(
        cr : ^cairo_t,
        red, green, blue : c.double,
    ) ---
    // Adds a circular arc of the given radius to the current path. The arc is centered at (xc, yc), begins at angle1 and proceeds in the direction of increasing angles to end at angle2 . If angle2 is less than angle1 it will be progressively increased by 2*M_PI until it is greater than angle1 .
    // If there is a current point, an initial line segment will be added to the path to connect the current point to the beginning of the arc. If this initial line is undesired, it can be avoided by calling cairo_new_sub_path() before calling cairo_arc().
    // Angles are measured in radians. An angle of 0.0 is in the direction of the positive X axis (in user space). An angle of M_PI/2.0 radians (90 degrees) is in the direction of the positive Y axis (in user space). Angles increase in the direction from the positive X axis toward the positive Y axis. So with the default transformation matrix, angles increase in a clockwise direction.
    arc :: proc(
        cr : ^cairo_t,
        xc, yc : c.double,
        radius : c.double,         // In degrees
        angle1, angle2 : c.double, // In radians
    ) ---
    // A drawing operator that paints the current source everywhere within the current clip region.
    paint :: proc(
        cr : ^cairo_t,
    ) ---
    // A drawing operator that fills the current path according to the current fill rule, (each sub-path is implicitly closed before being filled). After cairo_fill(), the current path will be cleared from the cairo context. See cairo_set_fill_rule() and cairo_fill_preserve().
    fill :: proc(
        cr : ^cairo_t,
    ) ---
    // A drawing operator that fills the current path according to the current fill rule, (each sub-path is implicitly closed before being filled). Unlike cairo_fill(), cairo_fill_preserve() preserves the path within the cairo context.
    fill_preserve :: proc(
        cr : ^cairo_t,
    ) ---
    // A drawing operator that strokes the current path according to the current line width, line join, line cap, and dash settings. After cairo_stroke(), the current path will be cleared from the cairo context. See cairo_set_line_width(), cairo_set_line_join(), cairo_set_line_cap(), cairo_set_dash(), and cairo_stroke_preserve().
    stroke :: proc(
        cr : ^cairo_t,
    ) ---
    // A drawing operator that strokes the current path according to the current line width, line join, line cap, and dash settings. Unlike cairo_stroke(), cairo_stroke_preserve() preserves the path within the cairo context.
    stroke_preserve :: proc(
        cr : ^cairo_t,
    ) ---
}
