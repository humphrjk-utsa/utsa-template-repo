#!/bin/bash
# Lightweight postCreateCommand — everything is pre-installed in the Docker image.
# This script only configures per-instance settings (git, postgres user, bashrc).

set -e
echo "🚀 Configuring codespace instance..."
START_TIME=$(date +%s)

# Initialize conda for bash
if ! grep -q "conda initialize" ~/.bashrc 2>/dev/null; then
    conda init bash
fi
source ~/.bashrc 2>/dev/null || true

# ============================================
# Git config (classroom defaults)
# ============================================
git config --global init.defaultBranch main
git config --global commit.gpgsign false
git config --global tag.gpgsign false
git config --global user.name "Data Science Student" 2>/dev/null || true
git config --global user.email "student@example.com" 2>/dev/null || true

# ============================================
# PostgreSQL: create student user & databases
# ============================================
echo "🗄️ Setting up PostgreSQL..."
sudo service postgresql start
sleep 2

# 'student' is the single default & admin user for the classroom database.
# SUPERUSER + CREATEDB lets students do anything (create tables, load CSVs,
# create databases, GRANT, etc.) without permission errors.
sudo -u postgres psql -c "CREATE USER student WITH SUPERUSER CREATEDB;" 2>/dev/null || \
sudo -u postgres psql -c "ALTER USER student WITH SUPERUSER CREATEDB;" 2>/dev/null || true
sudo -u postgres psql -c "ALTER USER student WITH PASSWORD NULL;" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE student_db OWNER student;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE postgres TO student;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE student_db TO student;" 2>/dev/null || true
sudo -u postgres psql -c "ALTER DATABASE postgres OWNER TO student;" 2>/dev/null || true

# Remove legacy 'vscode' role if it exists — student is the sole admin now.
sudo -u postgres psql -c "DROP OWNED BY vscode;" 2>/dev/null || true
sudo -u postgres psql -c "DROP USER vscode;" 2>/dev/null || true

# Load sample databases if SQL files exist
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d "$WORKSPACE_DIR/databases" ]; then
    for sql_file in $WORKSPACE_DIR/databases/*.sql; do
        [ -f "$sql_file" ] || continue
        db_name=$(basename "$sql_file" .sql)
        echo "  📊 Loading $db_name..."
        psql -U student -h localhost -d postgres -f "$sql_file" 2>/dev/null || true
    done
fi

# ============================================
# Bashrc: PostgreSQL aliases (add once)
# ============================================
if ! grep -q "PGUSER=student" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'BASHRC'

# PostgreSQL environment - student user (no password, trust auth)
export PGUSER=student
export PGDATABASE=postgres
export PGHOST=localhost
export PGPORT=5432

# Quick commands
alias pg_start='sudo service postgresql start'
alias pg_stop='sudo service postgresql stop'
alias pg_status='sudo service postgresql status'
alias pg_restart='sudo service postgresql restart'
alias db='psql -U student -h localhost postgres'
# check_status alias - works from any workspace
alias check_status='bash $(find /workspaces -maxdepth 2 -name "check_environment.sh" 2>/dev/null | head -1)'
BASHRC
fi

source ~/.bashrc 2>/dev/null || true

# ============================================
# Quick verification
# ============================================
echo ""
echo "✅ Verifying environment..."
echo "   R:          $(R --version 2>&1 | head -1 | cut -d' ' -f3)"
echo "   Python:     $(python --version 2>&1 | cut -d' ' -f2)"
echo "   PostgreSQL: $(postgres --version 2>/dev/null | cut -d' ' -f3 || echo 'installed')"
echo "   Kernels:    $(jupyter kernelspec list 2>/dev/null | grep -c '  ') available"

# Quick R package check
R --quiet --no-save -e '
pkgs <- c("mlba","tidyverse","caret","Hmisc","psych","pastecs","e1071",
          "fastDummies","writexl","readxl","languageserver","httpgd","IRkernel",
          "FactoMineR","factoextra","pls","conjoint","lavaan","DiscriMiner","cluster")
missing <- pkgs[!sapply(pkgs, requireNamespace, quietly=TRUE)]
if (length(missing)==0) cat("   R packages: all OK\n") else cat("   R packages missing:", paste(missing, collapse=", "), "\n")
' 2>/dev/null

END_TIME=$(date +%s)
echo ""
echo "════════════════════════════════════════════"
echo "✅ Ready in $((END_TIME - START_TIME))s"
echo "════════════════════════════════════════════"
