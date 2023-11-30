import os

# To use directly, use this:
#    dmgbuild -s dmg_settings.py "My App" MyApp.dmg
#
# To specify a different App location:
#    dmgbuild -s dmg_settings.py -D app=/path/to/My.app "My Application" MyApp.dmg

# Application settings
application = defines.get('app', 'MyApp.app')
appname = os.path.basename(application)

# Volume format (see hdiutil create -help)
format = defines.get('format', 'UDBZ')

# Volume size (must be large enough for your files)
#size = defines.get('size', '300M')

# Files to include
files = [ application ]

# Symlinks to create
symlinks = { 'Applications': '/Applications' }

icon_locations = {
    appname:        (161, 150),
    'Applications': (432, 150), #422
}

# Background
#background = 'background.tiff'

# Window configuration
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
#sidebar_width = 180
default_view = 'icon-view'

window_rect = ((200, 120), (600, 360))

# Volume icon or badge icon
#icon = 'disk_image.icns'
#badge_icon = '/path/to/icon.icns'

# General view configuration
show_icon_preview = False

# Icon view configuration
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = 'bottom' # or 'right'
text_size = 16 # 14
icon_size = 180 # 220
