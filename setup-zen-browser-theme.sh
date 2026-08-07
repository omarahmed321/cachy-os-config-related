#!/usr/bin/env bash
#===============================================================================
#   Original Glassy / Transparent & Borderless Zen Browser Theme
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachyos-restore
#===============================================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << "EOF"
  ==============================================================
    Glassy / Transparent & Borderless Zen Browser Theme Setup
  ==============================================================
EOF
echo -e "${NC}"

echo -e "${CYAN}[+] Configuring Glassy/Transparent & Borderless Zen Browser UI...${NC}"

# Pre-seed default Zen Browser profiles if they don't exist yet
mkdir -p "$HOME/.config/zen"
if [ ! -f "$HOME/.config/zen/profiles.ini" ]; then
    echo -e "${CYAN}Pre-seeding Zen Browser profiles.ini and default profile directories...${NC}"
    cat << 'EOF_INI' > "$HOME/.config/zen/profiles.ini"
[Profile1]
Name=Default Profile
IsRelative=1
Path=081dvyif.Default Profile
Default=1

[Profile0]
Name=Default (release)
IsRelative=1
Path=l1u1cimb.Default (release)

[General]
StartWithLastProfile=1
Version=2

[Install15B76BAA26BA15E7]
Default=l1u1cimb.Default (release)
Locked=1
EOF_INI
    mkdir -p "$HOME/.config/zen/081dvyif.Default Profile"
    mkdir -p "$HOME/.config/zen/l1u1cimb.Default (release)"
fi

ZEN_PROFILES=()
while IFS= read -r -d '' dir; do
    ZEN_PROFILES+=("$dir")
done < <(find "$HOME/.config/zen" -maxdepth 1 -type d -name "*Default*" -print0 2>/dev/null)

if [ ${#ZEN_PROFILES[@]} -gt 0 ]; then
    for profile in "${ZEN_PROFILES[@]}"; do
        echo -e "Configuring Zen Browser profile: ${CYAN}$(basename "$profile")${NC}"
        mkdir -p "$profile/chrome"
        
        # Write userChrome.css (Transparent & Borderless Terminal Style with Solid Web Content Viewport)
        cat << 'ZENCHROME' > "$profile/chrome/userChrome.css"
/*
 * Zen Browser - Glassy UI Chrome & Clean Web Content Viewport
 */

/* Window & Topbar Shell Transparency (Glassy Chrome UI) */
:root,
#main-window,
#navigator-toolbox,
#nav-bar,
#titlebar,
#TabsToolbar,
#zen-appcontent-navbar-container,
#zen-sidebar-top-buttons {
    background-color: transparent !important;
    background: transparent !important;
    border: none !important;
    box-shadow: none !important;
    outline: none !important;
}

/* Remove default splitters, borders and status boxes */
#zen-sidebar-splitter,
#appcontent-splitter {
    display: none !important;
    width: 0 !important;
    visibility: collapse !important;
}

#statuspanel,
#browser-bottombox {
    display: none !important;
    visibility: collapse !important;
}

/* Solid Web Content Container (Prevents wallpaper leakage into web pages) */
#appcontent,
#tabbrowser-tabpanels,
.browserSidebarContainer,
#content-deck,
#tabbrowser-deck {
    background-color: #0e0f0e !important;
    border: none !important;
    box-shadow: none !important;
}

/* Rounded frame for web content area */
#appcontent {
    border-radius: 6px !important;
}
ZENCHROME

        # Write userContent.css
        cat << 'ZENCONTENT' > "$profile/chrome/userContent.css"
/*
 * Zen Browser - Web Content Font & Page Optimization
 */

/* Empty / New Tab page background */
@-moz-document url("about:blank"), url("about:newtab"), url("about:home") {
    :root, body, html {
        background-color: #0e0f0e !important;
    }
}

/* Smooth font rendering on all websites */
@-moz-document url-prefix(http), url-prefix(https), url-prefix(about:) {
    body, p, span, a, li, h1, h2, h3, h4, h5, h6, input, textarea, button {
        -webkit-font-smoothing: antialiased !important;
        -moz-osx-font-smoothing: grayscale !important;
        text-rendering: optimizeLegibility !important;
    }
}
ZENCONTENT

        # Write user.js
        cat << 'ZENUSERJS' > "$profile/user.js"
// Enable userChrome.css customizations
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Enable native Linux window transparency in Zen Browser
user_pref("browser.tabs.allow_transparent_browser", true);
user_pref("widget.transparent-windows", true);
user_pref("zen.widget.linux.transparency", true);

// Enable Compact Mode
user_pref("zen.view.compact.enable-at-startup", true);
user_pref("zen.view.compact.toolbar-flash-popup", false);
user_pref("zen.view.compact.hide-toolbar", true);

// Disable the hover-to-reveal sidebar and toolbar in compact mode
user_pref("zen.view.compact.show-sidebar-and-toolbar-on-hover", false);

// Remove the default 8px frame/borders around the browser content
user_pref("zen.theme.content-element-separation", 0);

// Collapse sidebar and hide tabs
user_pref("zen.view.sidebar-expanded", false);
user_pref("zen.view.use-single-toolbar", true);
user_pref("zen.tabs.show-newtab-vertical", false);
user_pref("zen.view.show-newtab-button-top", false);

// Floating URL bar behavior
user_pref("zen.urlbar.behavior", "float");

// New tab = blank page
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.startup.page", 1);
user_pref("zen.urlbar.replace-newtab", false);

// Disable session restore
user_pref("browser.sessionstore.resume_session_once", false);
user_pref("browser.sessionstore.resume_from_crash", false);

// Font optimizations
user_pref("font.size.variable.x-western", 18);
user_pref("font.size.fixed.x-western", 15);
user_pref("font.minimum-size.x-western", 13);
ZENUSERJS

        # Also force legacy stylesheets option in prefs.js if it exists
        PREFS_FILE="$profile/prefs.js"
        if [ -f "$PREFS_FILE" ]; then
            if grep -q "toolkit.legacyUserProfileCustomizations.stylesheets" "$PREFS_FILE"; then
                sed -i 's/user_pref("toolkit.legacyUserProfileCustomizations.stylesheets",.*/user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);/' "$PREFS_FILE"
            else
                echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$PREFS_FILE"
            fi
        fi
    done
    echo -e "${GREEN}[OK] Glassy & Borderless Zen Browser theme applied successfully to all profiles!${NC}"
else
    echo -e "${YELLOW}[INFO] No Zen Browser profile found in ~/.config/zen/. Skipping configuration.${NC}"
fi

# Copy script to user bin
mkdir -p "$HOME/.local/share/bin"
cp "$0" "$HOME/.local/share/bin/setup-zen-browser-theme.sh" 2>/dev/null || true
chmod +x "$HOME/.local/share/bin/setup-zen-browser-theme.sh" 2>/dev/null || true
