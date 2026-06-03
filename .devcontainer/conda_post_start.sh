#!/bin/bash
# postStartCommand — runs every time the codespace starts/resumes.
# Only starts services; everything else is baked into the Docker image.

echo "🔄 Starting services..."
source ~/.bashrc 2>/dev/null || true

# Start PostgreSQL
if ! sudo -n service postgresql status >/dev/null 2>&1; then
    sudo service postgresql start
    sleep 2
fi
echo "✅ PostgreSQL running"

# Ensure student user exists with full admin rights (idempotent)
sudo -u postgres psql -c "CREATE USER student WITH SUPERUSER CREATEDB;" 2>/dev/null || \
sudo -u postgres psql -c "ALTER USER student WITH SUPERUSER CREATEDB;" 2>/dev/null || true
sudo -u postgres psql -c "ALTER USER student WITH PASSWORD NULL;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE postgres TO student;" 2>/dev/null || true

# Drop legacy 'vscode' role so 'student' is the sole admin
sudo -u postgres psql -c "REASSIGN OWNED BY vscode TO student;" 2>/dev/null || true
sudo -u postgres psql -c "DROP OWNED BY vscode;" 2>/dev/null || true
sudo -u postgres psql -c "DROP USER vscode;" 2>/dev/null || true

# Load sample databases if they exist and haven't been loaded
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d "$WORKSPACE_DIR/databases" ]; then
    for sql_file in $WORKSPACE_DIR/databases/*.sql; do
        [ -f "$sql_file" ] || continue
        db_name=$(basename "$sql_file" .sql)
        psql -U student -h localhost -d postgres -f "$sql_file" 2>/dev/null || true
    done
fi

# ============================================
# R kernel: guarantee it is registered and visible
# ============================================
# Students have reported needing to rebuild the container to get the R
# kernel to appear. This block makes registration idempotent and self-healing:
#   1. If the global kernelspec is missing, reinstall it.
#   2. If the global location is not writable (rare), fall back to user spec.
#   3. Always refresh kernelspec cache so VS Code Jupyter picks it up.
GLOBAL_IR=/opt/conda/share/jupyter/kernels/ir/kernel.json
USER_IR="$HOME/.local/share/jupyter/kernels/ir/kernel.json"

# Always ensure the USER-level kernelspec exists. VS Code's Jupyter extension
# reliably discovers user-level kernels; the conda-global location is sometimes
# filtered out, causing the "R kernel doesn't show up in notebooks" issue.
if [ ! -f "$USER_IR" ]; then
    echo "🔧 Registering R kernel at user level..."
    R --quiet --no-save -e "IRkernel::installspec(user=TRUE, name='ir', displayname='R')" \
        >/dev/null 2>&1
fi

# Also ensure global kernelspec exists (defensive, for non-VS-Code Jupyter clients)
if [ ! -f "$GLOBAL_IR" ] && [ -w /opt/conda/share/jupyter/kernels ] 2>/dev/null; then
    R --quiet --no-save -e "IRkernel::installspec(user=FALSE, name='ir', displayname='R')" \
        >/dev/null 2>&1 || true
fi

# Refresh kernelspec cache (helps VS Code Jupyter detect kernels without restart)
jupyter kernelspec list >/dev/null 2>&1
touch "$GLOBAL_IR" 2>/dev/null || true
touch "$USER_IR" 2>/dev/null || true

if jupyter kernelspec list 2>/dev/null | grep -q '\bir\b'; then
    echo "✅ R kernel registered"
else
    echo "⚠️  R kernel still missing — run: R -e \"IRkernel::installspec(user=TRUE)\""
fi

# Ensure user R library exists and is writable so students can install.packages()
mkdir -p "$HOME/R/library"

# Ensure Git config (classroom: never sign commits, no matter what
# /etc/gitconfig or a stale repo-local override says)
git config --global commit.gpgsign false 2>/dev/null || true
git config --global tag.gpgsign false 2>/dev/null || true
git config --unset commit.gpgsign 2>/dev/null || true
git config --unset tag.gpgsign 2>/dev/null || true

echo ""
echo "════════════════════════════════════════════"
echo "✅ Environment ready for data science work!"
echo "════════════════════════════════════════════"
