#!/bin/bash
# Environment Status Checker for Students
# Run this to see what's working and what needs fixing

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         🎓 Data Science Environment Status Check             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

ISSUES=0

# ============================================
# Check R
# ============================================
echo "📊 R Environment:"
if command -v R &> /dev/null; then
    R_VERSION=$(R --version 2>&1 | head -1 | cut -d' ' -f3)
    echo "   ✅ R version $R_VERSION installed"
else
    echo "   ❌ R not found"
    ((ISSUES++))
fi

# Check R kernel
if jupyter kernelspec list 2>/dev/null | grep -qE '^\s*ir\s'; then
    echo "   ✅ R kernel registered with Jupyter"
else
    echo "   ❌ R kernel not registered"
    echo "      Fix: R -e \"IRkernel::installspec(user=TRUE, name='ir', displayname='R')\""
    ((ISSUES++))
fi

# Check user R library is writable (so install.packages() works for students)
USER_R_LIB="$HOME/R/library"
if [ -d "$USER_R_LIB" ] && [ -w "$USER_R_LIB" ]; then
    echo "   ✅ User R library writable ($USER_R_LIB)"
else
    echo "   ⚠️  User R library missing or read-only: $USER_R_LIB"
    mkdir -p "$USER_R_LIB" 2>/dev/null || true
fi

# Check mlba package
R --quiet --no-save << 'EOF' 2>/dev/null
if (requireNamespace("mlba", quietly = TRUE)) {
    cat("   ✅ mlba package installed\n")
} else {
    cat("   ❌ mlba package missing\n")
    cat("      Fix: devtools::install_github('gedeck/mlba/mlba')\n")
}
EOF

# Check other key packages
echo ""
echo "   Key R packages:"
R --quiet --no-save << 'EOF' 2>/dev/null
pkgs <- c("tidyverse", "caret", "Hmisc", "psych", "pastecs", "e1071", "fastDummies")
for (pkg in pkgs) {
    if (requireNamespace(pkg, quietly = TRUE)) {
        cat(sprintf("   ✅ %s\n", pkg))
    } else {
        cat(sprintf("   ❌ %s (install.packages('%s'))\n", pkg, pkg))
    }
}
EOF

# ============================================
# Check PostgreSQL
# ============================================
echo ""
echo "🗄️ PostgreSQL:"
if command -v psql &> /dev/null; then
    PG_VERSION=$(psql --version 2>/dev/null | cut -d' ' -f3 || echo "unknown")
    echo "   ✅ PostgreSQL $PG_VERSION installed"
else
    echo "   ❌ PostgreSQL client not installed"
    ((ISSUES++))
fi

# Check if PostgreSQL service is running
if sudo -n service postgresql status >/dev/null 2>&1; then
    echo "   ✅ PostgreSQL service running"
elif psql -U student -h localhost -c "SELECT 1;" >/dev/null 2>&1; then
    echo "   ✅ PostgreSQL running (student connection works)"
else
    echo "   ⚠️ PostgreSQL not running (use: pg_start)"
fi

# Check student user connection
if psql -U student -h localhost -c "SELECT current_user;" >/dev/null 2>&1; then
    echo "   ✅ Student user can connect (no password)"
else
    echo "   ⚠️ Student user cannot connect"
fi

# ============================================
# Check Python
# ============================================
echo ""
echo "🐍 Python Environment:"
PYTHON_VERSION=$(python --version 2>&1 | cut -d' ' -f2)
echo "   ✅ Python $PYTHON_VERSION"

# Check key Python packages
python << 'EOF' 2>/dev/null
import sys
packages = ['pandas', 'numpy', 'matplotlib', 'sqlalchemy', 'psycopg2']
for pkg in packages:
    try:
        __import__(pkg)
        print(f"   ✅ {pkg}")
    except ImportError:
        print(f"   ❌ {pkg}")
EOF

# ============================================
# Check Git
# ============================================
echo ""
echo "📝 Git Configuration:"
if git config --get user.name >/dev/null 2>&1; then
    echo "   ✅ User: $(git config --get user.name)"
else
    echo "   ⚠️ Git user name not set"
fi

GPG_SIGN=$(git config --get commit.gpgsign 2>/dev/null || echo "not set")
if [ "$GPG_SIGN" = "false" ]; then
    echo "   ✅ GPG signing disabled (good for classroom)"
else
    echo "   ⚠️ GPG signing enabled (may cause commit issues)"
fi

# ============================================
# Check Jupyter
# ============================================
echo ""
echo "📓 Jupyter:"
if [ -f ~/.jupyter/jupyter_server_config.py ]; then
    echo "   ✅ Jupyter configured for classroom"
else
    echo "   ⚠️ Jupyter config missing"
fi

KERNELS=$(jupyter kernelspec list 2>/dev/null | grep -c "  ")
echo "   ✅ $KERNELS kernel(s) available"

# ============================================
# Summary
# ============================================
echo ""
echo "════════════════════════════════════════════════════════════════"
if [ $ISSUES -eq 0 ]; then
    echo "✅ All systems operational! You're ready to work."
else
    echo "⚠️ Found $ISSUES issue(s). Run the fixes shown above."
    echo ""
    WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    echo "Or run full setup: bash $WORKSPACE_DIR/.devcontainer/conda_setup.sh"
fi
echo "════════════════════════════════════════════════════════════════"
echo ""
