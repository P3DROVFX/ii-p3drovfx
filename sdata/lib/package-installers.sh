# This script depends on `functions.sh' .
# This script is not for direct execution, instead it should be sourced by other script. It does not need execution permission or shebang.

# shellcheck shell=bash

# This file is provided for any distros, mainly non-Arch(based) distros.

install-Rubik(){
  x mkdir -p $REPO_ROOT/cache/Rubik
  x cd $REPO_ROOT/cache/Rubik
  try git init -b main
  try git remote add origin https://github.com/googlefonts/rubik.git
  x git pull origin main && git submodule update --init --recursive
	x sudo mkdir -p /usr/local/share/fonts/TTF/
	x sudo cp fonts/variable/Rubik*.ttf /usr/local/share/fonts/TTF/
	x sudo mkdir -p /usr/local/share/licenses/ttf-rubik/
	x sudo cp OFL.txt /usr/local/share/licenses/ttf-rubik/LICENSE
  x fc-cache -fv
  x cd $REPO_ROOT
}

install-Gabarito(){
  x mkdir -p $REPO_ROOT/cache/Gabarito
  x cd $REPO_ROOT/cache/Gabarito
  try git init -b main
  try git remote add origin https://github.com/naipefoundry/gabarito.git
  x git pull origin main && git submodule update --init --recursive
	x sudo mkdir -p /usr/local/share/fonts/TTF/
	x sudo cp fonts/ttf/Gabarito*.ttf /usr/local/share/fonts/TTF/
	x sudo mkdir -p /usr/local/share/licenses/ttf-gabarito/
	x sudo cp OFL.txt /usr/local/share/licenses/ttf-gabarito/LICENSE
  x fc-cache -fv
  x cd $REPO_ROOT
}

install-bibata(){
  x mkdir -p $REPO_ROOT/cache/bibata-cursor
  x cd $REPO_ROOT/cache/bibata-cursor
  name="Bibata-Modern-Classic"
  file="$name.tar.xz"
  try rm $file
  x curl -JLO https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/$file
  tar -xf $file
  x sudo mkdir -p /usr/local/share/icons
  x sudo cp -r $name /usr/local/share/icons
  x cd $REPO_ROOT
}

install-MicroTeX(){
  x mkdir -p $REPO_ROOT/cache/MicroTeX
  x cd $REPO_ROOT/cache/MicroTeX
  try git init -b master
  try git remote add origin https://github.com/NanoMichael/MicroTeX.git
  x git pull origin master && git submodule update --init --recursive
  x mkdir -p build
  x cd build
  x cmake ..
  x make -j32
	x sudo mkdir -p /opt/MicroTeX
  x sudo cp ./LaTeX /opt/MicroTeX/
  x sudo cp -r ./res /opt/MicroTeX/
  x cd $REPO_ROOT
}

install-uv(){
  x bash <(curl -LJs "https://astral.sh/uv/install.sh")
}

install-python-packages(){
  export UV_NO_MODIFY_PATH=1
  export UV_PYTHON_DOWNLOADS=automatic
  local venv_dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/.venv"
  x mkdir -p "$venv_dir"

  if ! command -v uv >/dev/null 2>&1; then
    echo -e "${STY_YELLOW}[$0]: \"uv\" not found. Installing uv...${STY_RST}"
    showfun install-uv
    v install-uv
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  fi

  # Attempt to create virtual environment with Python 3.12 via uv
  # (UV_PYTHON_DOWNLOADS=automatic downloads managed Python 3.12 if not on host)
  if ! uv venv --prompt .venv "$venv_dir" -p 3.12 --allow-existing; then
    echo -e "${STY_YELLOW}[$0]: uv venv with Python 3.12 failed. Attempting uv python install 3.12...${STY_RST}"
    if uv python install 3.12; then
      uv venv --prompt .venv "$venv_dir" -p 3.12 --allow-existing
    else
      echo -e "${STY_YELLOW}[$0]: Falling back to system python3 for venv...${STY_RST}"
      uv venv --prompt .venv "$venv_dir" --allow-existing || python3 -m venv "$venv_dir"
    fi
  fi

  if [ ! -f "$venv_dir/bin/activate" ]; then
    echo -e "${STY_RED}[$0]: Virtualenv activate script not found. Forcing python3 -m venv...${STY_RST}"
    python3 -m venv "$venv_dir"
  fi

  x source "$venv_dir/bin/activate"
  if [[ "$INSTALL_VIA_NIX" = true ]]; then
    x nix-shell "${REPO_ROOT}/sdata/uv/shell.nix" --run "uv pip install -r ${REPO_ROOT}/sdata/uv/requirements.txt || uv pip install -r ${REPO_ROOT}/sdata/uv/requirements.in"
  else
    if ! uv pip install -r "${REPO_ROOT}/sdata/uv/requirements.txt"; then
      echo -e "${STY_YELLOW}[$0]: Exact requirements failed. Trying requirements.in...${STY_RST}"
      x uv pip install -r "${REPO_ROOT}/sdata/uv/requirements.in"
    fi
  fi
  x deactivate
}
