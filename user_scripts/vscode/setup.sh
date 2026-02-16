#!/bin/bash
set -e
cd ~
curl -L -o material-code3.1.1.vsix https://archive.org/download/material-code3.1.1/material-code3.1.1.vsix
vscodium --install-extension ~/material-code3.1.1.vsix
rm ~/material-code3.1.1.vsix
~/user_scripts/theme_matugen/theme_ctl.sh refresh
