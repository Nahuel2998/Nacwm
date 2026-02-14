package pango

import "core:c"
import "../cairo"

// The scale between dimensions used for Pango distances and device units.
// The definition of device units is dependent on the output device; it will typically be pixels for a screen, and points for a printer. %PANGO_SCALE is currently 1024, but this may be changed in the future.
// When setting font sizes, device units are always considered to be points (as in "12 point font"), rather than pixels.
SCALE :: 1024

// The PangoLayout structure represents an entire paragraph of text. It is initialized with a PangoContext, UTF-8 string and set of attributes for that string. Once that is done, the set of formatted lines can be extracted from the object, the layout can be rendered, and conversion between logical character positions within the layout's text, and the physical position of the resulting glyphs can be made.
Layout :: struct{}
// The PangoFontDescription structure represents the description of an ideal font. These structures are used both to list what fonts are available on the system and also for specifying the characteristics of a font to load.
FontDescription :: struct{}

// The PangoEllipsizeMode type describes what sort of (if any) ellipsization should be applied to a line of text. In the ellipsization process characters are removed from the text in order to make it fit to a given width and replaced with an ellipsis.
EllipsizeMode :: enum {
    None,   // No ellipsization
    Start,  // Omit characters at the start of the text
    Middle, // Omit characters in the middle of the text
    End,    // Omit characters at the end of the text
}

foreign import pango "system:pango-1.0"
@(default_calling_convention="c", link_prefix="pango_")
foreign pango {
    // Creates a new font description from a string representation in the form "FAMILY-LIST [SIZE]", where FAMILY-LIST is a comma separated list of families optionally terminated by a comma, STYLE_OPTIONS is a whitespace separated list of words where each word describes one of style, variant, weight, stretch, or gravity, and SIZE is a decimal number (size in points) or optionally followed by the unit modifier "px" for absolute size. Any one of the options may be absent. If FAMILY-LIST is absent, then the family_name field of the resulting font description will be initialized to NULL. If STYLE-OPTIONS is missing, then all style options will be set to the default values. If SIZE is missing, the size in the resulting font description will be set to 0.
    font_description_from_string :: proc(
        str : cstring,
    ) -> ^FontDescription ---
    // Frees a font description.
    font_description_free :: proc(
        desc : ^FontDescription,
    ) ---
    // Sets the default font description for the layout. If no font description is set on the layout, the font description from the layout's context is used.
    layout_set_font_description :: proc(
        layout : ^Layout,
        desc   : ^FontDescription,
    ) ---
    // Sets the text of the layout.
    // Note that if you have used pango_layout_set_markup() or pango_layout_set_markup_with_accel() on layout before, you may want to call pango_layout_set_attributes() to clear the attributes set on the layout from the markup as this function does not clear attributes.
    layout_set_text :: proc(
        layout : ^Layout,
        text   : cstring,
        length : c.int,
    ) ---
    // Sets the width to which the lines of the PangoLayout should wrap or ellipsized. The default value is -1: no width set.
    layout_set_width :: proc(
        layout : ^Layout,
        width  : c.int,
    ) ---
    // Sets the type of ellipsization being performed for layout . Depending on the ellipsization mode ellipsize text is removed from the start, middle, or end of text so they fit within the width and height of layout set with pango_layout_set_width() and pango_layout_set_height().
    // If the layout contains characters such as newlines that force it to be layed out in multiple paragraphs, then whether each paragraph is ellipsized separately or the entire layout is ellipsized as a whole depends on the set height of the layout. See pango_layout_set_height() for details.
    layout_set_ellipsize :: proc(
        layout    : ^Layout,
        ellipsize : EllipsizeMode,
    ) ---
    // Determines the logical width and height of a PangoLayout in device units. (pango_layout_get_size() returns the width and height scaled by PANGO_SCALE.) This is simply a convenience function around pango_layout_get_pixel_extents().
    layout_get_pixel_size :: proc(
        layout : ^Layout,
        width, height : ^c.int,
    ) ---
}

foreign import pangocairo "system:pangocairo-1.0"
@(default_calling_convention="c", link_prefix="pango_")
foreign pangocairo {
    // Creates a layout object set up to match the current transformation and target surface of the Cairo context. This layout can then be used for text measurement with functions like pango_layout_get_size() or drawing with functions like pango_cairo_show_layout(). If you change the transformation or target surface for cr, you need to call pango_cairo_update_layout()
    // This function is the most convenient way to use Cairo with Pango, however it is slightly inefficient since it creates a separate PangoContext object for each layout. This might matter in an application that was laying out large amounts of text.
    cairo_create_layout :: proc(
        cr : ^cairo.cairo_t,
    ) -> ^Layout ---
    // Draws a PangoLayout in the specified cairo context.
    // The top-left corner of the PangoLayout will be drawn at the current point of the cairo context.
    cairo_show_layout :: proc(
        cr     : ^cairo.cairo_t,
        layout : ^Layout,
    ) ---
}

foreign import gobject "system:gobject-2.0"
@(default_calling_convention="c", link_prefix="g_object_")
foreign gobject {
    // Decreases the reference count of object. When its reference count drops to 0, the object is finalized (i.e. its memory is freed).
    // If the pointer to the GObject may be reused in future (for example, if it is an instance variable of another object), it is recommended to clear the pointer to NULL rather than retain a dangling pointer to a potentially invalid GObject instance. Use g_clear_object() for this.
    unref :: proc(
        object : rawptr,
    ) ---
}
