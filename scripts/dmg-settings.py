# dmgbuild settings for Quitty.dmg; see scripts/build-dmg.sh.
# `defines` is provided by dmgbuild from its -D options.
import os.path

application = defines["app"]  # noqa: F821
appname = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon")  # noqa: F821
background = defines["background"]  # noqa: F821

# Matches the 660×400 background drawn by scripts/make-assets.py.
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
label_pos = "bottom"
text_size = 13
icon_size = 128
icon_locations = {
    appname: (180, 185),
    "Applications": (480, 185),
}
