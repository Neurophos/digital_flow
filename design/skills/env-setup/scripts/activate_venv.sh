#!/bin/bash
# =======================================================================================
# Copyright (C) Neurophos, Inc - All Rights Reserved
# Proprietary and confidential
# -------------------------------------------------------------------------------
# TITLE : Virtual Environment Activation Script
# FILE  : activate_venv.sh
# DESCRIPTION : Activates the Python virtual environment for MSIC project
#              
# STANDARD    : Bash
# REVISIONS   :
# VERSION     : 1.0
# =======================================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/scripts/venv"

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo "Error: Virtual environment not found at $VENV_DIR"
    echo "Please run: python3 -m venv scripts/venv"
    exit 1
fi

# Check if activation script exists
if [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "Error: Virtual environment activation script not found"
    echo "Virtual environment may be corrupted. Please recreate it."
    exit 1
fi

# Activate the virtual environment
echo "Activating Python virtual environment..."
source "$VENV_DIR/bin/activate"

# Verify activation by checking if python3 is available and in the venv
if command -v python3 >/dev/null 2>&1 && python3 -c "import sys; print(sys.prefix)" | grep -q "scripts/venv"; then
    echo "✓ Virtual environment activated successfully"
    echo "Python version: $(python3 --version)"
    echo "Pip version: $(pip --version)"
    echo ""
    echo "Available Python packages:"
    pip list --format=columns
else
    echo "Error: Failed to activate virtual environment"
    echo "VIRTUAL_ENV: $VIRTUAL_ENV"
    echo "Expected: $VENV_DIR"
    exit 1
fi
