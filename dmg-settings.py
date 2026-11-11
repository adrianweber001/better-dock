# Einstellungen für dmgbuild – erzeugt das DMG mit gestaltetem Fenster.
# Aufruf über ./build.sh dmg
#
# Die Positionen müssen zum Hintergrundbild passen (Assets/dmg-background.swift).
import os

app = defines.get("app", "Better Dock.app")

format = "UDZO"                      # komprimiert, nur lesbar
files = [app]
symlinks = {"Applications": "/Applications"}

background = "Assets/dmg-background.png"   # die @2x-Variante wird automatisch mitgenommen

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True

window_rect = ((240, 160), (660, 468))     # 440 Inhalt + Titelleiste
icon_size = 96
text_size = 12
arrange_by = None
icon_locations = {
    os.path.basename(app): (330, 160),
    "Applications": (330, 338),            # der leuchtende freie Platz im gezeichneten Dock
}
