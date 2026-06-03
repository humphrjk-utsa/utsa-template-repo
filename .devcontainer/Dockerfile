FROM quay.io/jupyter/datascience-notebook:latest

# ============================================================
# SYSTEM PACKAGES (as root)
# ============================================================
USER root

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  libnlopt-dev \
  cmake \
  postgresql \
  postgresql-contrib && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Passwordless sudo for jovyan (classroom use)
RUN echo 'jovyan ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/jovyan && \
  chmod 0440 /etc/sudoers.d/jovyan

# Configure PostgreSQL for trust auth (no passwords for classroom)
RUN echo "local all all trust" > /etc/postgresql/*/main/pg_hba.conf && \
  echo "host all all 127.0.0.1/32 trust" >> /etc/postgresql/*/main/pg_hba.conf && \
  echo "host all all ::1/128 trust" >> /etc/postgresql/*/main/pg_hba.conf

RUN chown -R jovyan:users /home/jovyan

# ============================================================
# ALL INSTALLS AS JOVYAN (no root needed after this)
# ============================================================
USER jovyan

# ---- Conda packages (binary, fast) ----
# Install as many R packages as possible via mamba (pre-compiled, instant)
RUN mamba install -c conda-forge -y --quiet \
  psycopg2 sqlalchemy plotly bokeh lxml beautifulsoup4 nodejs gh imagemagick \
  r-devtools r-remotes r-irkernel r-languageserver \
  r-tidyverse r-dplyr r-ggplot2 r-readr r-tidyr r-tibble \
  r-stringr r-forcats r-lubridate r-purrr \
  r-reshape2 r-data.table \
  r-dbi r-rsqlite r-dbplyr \
  r-knitr r-rmarkdown r-testthat \
  r-httr r-jsonlite r-rvest r-curl \
  r-hmisc r-psych r-e1071 r-caret r-broom r-scales \
  r-car r-mass r-multcomp r-ggpubr \
  r-corrplot r-factominer r-factoextra r-pls r-cluster r-igraph \
  r-gparotation r-lavaan r-diagrammer \
  r-class r-randomforest r-nnet \
  r-ggally r-gridextra r-ggrepel r-plotly r-rcolorbrewer r-forecast \
  r-writexl r-readxl && \
  mamba clean --all -f -y

# ---- Python packages (data science essentials) ----
RUN pip install --no-cache-dir \
  debugpy ipykernel \
  openpyxl xlrd xlsxwriter \
  statsmodels \
  ipython-sql \
  streamlit fastapi requests \
  pytest pytest-cov \
  black flake8 autopep8

# ---- R packages: Only packages NOT available in conda ----
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/jammy/latest')); \
  install.packages(c( \
  'httpgd', 'repr', 'IRdisplay', 'pbdZMQ', 'uuid', 'digest', \
  'reshape', 'fastDummies', 'RPostgreSQL', 'roxygen2', \
  'pastecs', 'correlation', \
  'effectsize', 'rstatix', 'AICcmodavg', 'mvnormalTest', 'heplots', \
  'corrr', 'ggcorrplot', \
  'nFactors', 'conjoint', 'lavaanPlot', \
  'ggdendro' \
  ), Ncpus=8)"

# ---- R packages: GitHub-only ----
RUN R -e "devtools::install_github('gedeck/mlba/mlba', force=TRUE, upgrade='never')" && \
  R -e "devtools::install_github('gastonstat/DiscriMiner', force=TRUE, upgrade='never')"

# ---- Register Jupyter kernels globally ----
# Install R kernel system-wide so every user/workspace sees it without re-registration.
# We also install it into the user prefix as a fallback so VS Code Jupyter always finds it.
RUN R -e "IRkernel::installspec(user=FALSE, name='ir', displayname='R')" && \
  # Also bake a user-level kernelspec into the image so VS Code's Jupyter
  # extension reliably discovers the R kernel without any post-start step.
  R -e "IRkernel::installspec(user=TRUE,  name='ir', displayname='R')" && \
  python3 -m ipykernel install --name python3 --display-name "Python 3" --sys-prefix && \
  # Make global kernel spec dir readable/writable so re-registration in postStart never fails
  chown -R jovyan:users /opt/conda/share/jupyter/kernels && \
  chmod -R u+rwX,g+rwX /opt/conda/share/jupyter/kernels && \
  jupyter kernelspec list

# ---- Jupyter config (no token/password for classroom) ----
RUN mkdir -p /home/jovyan/.jupyter && \
  echo "c.ServerApp.token = ''" > /home/jovyan/.jupyter/jupyter_server_config.py && \
  echo "c.ServerApp.password = ''" >> /home/jovyan/.jupyter/jupyter_server_config.py && \
  echo "c.ServerApp.open_browser = False" >> /home/jovyan/.jupyter/jupyter_server_config.py && \
  echo "c.ServerApp.ip = '0.0.0.0'" >> /home/jovyan/.jupyter/jupyter_server_config.py && \
  echo "c.ServerApp.allow_origin = '*'" >> /home/jovyan/.jupyter/jupyter_server_config.py && \
  echo "c.ServerApp.disable_check_xsrf = True" >> /home/jovyan/.jupyter/jupyter_server_config.py

# ---- R profile (user library + CRAN mirror) ----
# Pre-create the user library with correct ownership so students can
# install.packages() without permission errors. Also pin a fast CRAN mirror
# and set parallel compile cores for snappy installs.
RUN mkdir -p /home/jovyan/R/library && \
  chown -R jovyan:users /home/jovyan/R && \
  echo 'user_lib <- "~/R/library"' > /home/jovyan/.Rprofile && \
  echo 'if (!dir.exists(user_lib)) dir.create(user_lib, recursive = TRUE)' >> /home/jovyan/.Rprofile && \
  echo '.libPaths(c(user_lib, .libPaths()))' >> /home/jovyan/.Rprofile && \
  echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))' >> /home/jovyan/.Rprofile && \
  echo 'options(Ncpus = 4)' >> /home/jovyan/.Rprofile && \
  chown jovyan:users /home/jovyan/.Rprofile
