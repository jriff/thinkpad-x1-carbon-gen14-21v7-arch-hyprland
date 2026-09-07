-- accel_profile is "custom <step> <factors>". Each factor is the acceleration
-- at a multiple of step, thus the positions are:
--
--   custom  <step>  <f@0>  <f@1step>  <f@2step>  <f@3step>  <f@4step>  <f@5step>
--                    rest   slow  -------------------------------->   flick
--
-- f@0 stays 0. A non-zero value there moves the pointer under a resting
-- finger. Flat at the low end gives precision; steep at the top lets a flick
-- cross the screen.
--
-- CAUTION: These numbers fit the Goodix panel in this machine. Another panel
-- reports different deltas, thus the same numbers give a different feel. Tune
-- on the hardware. Do not copy.
-- NOTE: input.sensitivity in input.lua multiplies this. If the pointer is
-- uniformly too fast or too slow, change that, not these points.
-- scroll_points is the SAME format and applies to two-finger scroll.
-- CAUTION: Set it whenever accel_profile is custom. Scroll then follows the
-- pointer curve, which reaches 3.2, and a flick scrolls far too far.
hl.device({
    name          = "gxtp5420:00-27c6:0f95-touchpad",
    accel_profile = "custom 0.5 0.0 0.36 1.2 1.2 2.1 3.2",
    scroll_points = "1.0 0.0 0.11 0.29 0.6 1.05 1.5",
})

-- Terminal scroll, on top of the curve above. input.lua sets 1.5 for a machine
-- with no curve; this scroll curve reaches 1.5, thus a terminal needs more to
-- feel the same. Alacritty and foot scroll by lines, thus they need more than
-- an application that scrolls by pixels.
hl.window_rule({
    match           = { class = "(Alacritty|kitty|foot)" },
    scroll_touchpad = 3.8,
})
