#!/bin/bash

set -euo pipefail

# =============================================================================
# CONFIGURATION — Edit these variables before running
# =============================================================================

# Database
DB_PASSWORD="Tohnga123\$"
DB_PORT="1521"
DB_SERVICE="FREEPDB1"
ORACLE_SID="FREE"
ORACLE_HOME="/opt/oracle/product/23ai/dbhomeFree"
ORACLE_DB_DOWNLOAD_LINK="https://download.oracle.com/otn-pub/otn_software/db-free/oracle-database-free-23ai-1.0-1.el8.x86_64.rpm"

# APEX
APEX_DOWNLOAD_URL="https://download.oracle.com/otn_software/apex/apex_24.2_en.zip"
APEX_ADMIN_USER="ADMIN"
APEX_ADMIN_EMAIL="your.email@gmail.com"
APEX_ADMIN_PASSWORD="Tohnga123\$"
APEX_PUBLIC_USER_PASSWORD="admin123"
APEX_TABLESPACE="SYSAUX"
APEX_FILES_TABLESPACE="SYSAUX"
APEX_TEMP_TABLESPACE="TEMP"
APEX_IMAGES_PATH="/i/"

# ORDS
ORDS_VERSION="ords-26.2.3-3.el8"
ORDS_CONFIG_DIR="/etc/ords/config"
ORDS_STATIC_IMAGES="/opt/oracle/apex/images"
ORDS_CONTEXT_PATH="/ords"
ORDS_HTTP_PORT="8080"
ORDS_EXTERNAL_DOMAIN="https://your-own-domain.care"

# ORDS Connection Pool
ORDS_JDBC_INITIAL_LIMIT="15"
ORDS_JDBC_MAX_LIMIT="25"
ORDS_JDBC_MIN_LIMIT="15"

# Tomcat
TOMCAT_VERSION="9.0.111"
TOMCAT_DOWNLOAD_URL="https://repo.maven.apache.org/maven2/org/apache/tomcat/tomcat/${TOMCAT_VERSION}/tomcat-${TOMCAT_VERSION}.zip"
TOMCAT_INSTALL_DIR="/opt/tomcat"
TOMCAT_USER="tomcat"
TOMCAT_GROUP="tomcat"

# Directories
WORK_DIR="/tmp/apex_install"
LOG_FILE="/var/log/apex_install.log"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [OK]    $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}${msg}${NC}" >&2
    echo "$msg" >> "$LOG_FILE"
}

log_section() {
    local border="============================================="
    echo ""
    echo -e "${CYAN}${border}${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}${border}${NC}"
    echo ""
    echo "" >> "$LOG_FILE"
    echo "$border" >> "$LOG_FILE"
    echo "  $1" >> "$LOG_FILE"
    echo "$border" >> "$LOG_FILE"
}

# Error handler
on_error() {
    local line_no=$1
    local exit_code=$2
    log_error "Script failed at line ${line_no} with exit code ${exit_code}"
    log_error "Check the log file for details: ${LOG_FILE}"
    exit "$exit_code"
}

trap 'on_error ${LINENO} $?' ERR

# Run a command as the oracle user with the correct environment
run_as_oracle() {
    sudo -u oracle bash -c "
        export ORACLE_SID=${ORACLE_SID}
        export ORACLE_HOME=${ORACLE_HOME}
        export PATH=\${PATH}:${ORACLE_HOME}/bin
        $1
    "
}

# Run SQL as sysdba using a temporary SQL file (avoids quoting issues)
# Usage: run_sql_file <<'SQL'
#   ALTER SESSION SET CONTAINER = FREEPDB1;
#   EXIT;
# SQL
run_sql_file() {
    local sql_file
    sql_file=$(mktemp /tmp/apex_sql_XXXXXX.sql)
    cat > "$sql_file"
    chown oracle:oinstall "$sql_file"
    run_as_oracle "sqlplus -s / as sysdba @${sql_file}"
    rm -f "$sql_file"
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

# Must run as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root. Use: sudo ./unattended_apex_install.sh"
    exit 1
fi

# Start timer
START_TIME=$(date +%s)

# Create log file
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Create work directory
mkdir -p "$WORK_DIR"

log_section "Oracle APEX + ORDS + Tomcat Unattended Installer"
log_info "Log file: ${LOG_FILE}"
log_info "Work directory: ${WORK_DIR}"
log_info "Starting installation at $(date)"

# =============================================================================
# 1. INSTALL ORACLE DATABASE 23ai FREE
# =============================================================================

log_section "1/5 — Installing Oracle Database 23ai Free"

# Install prerequisites
log_info "Installing Oracle Database 23ai preinstall package..."
dnf install -y oracle-database-preinstall-23ai >> "$LOG_FILE" 2>&1
log_success "Preinstall package installed"

# Install Oracle Database
log_info "Installing Oracle Database 23ai Free (this may take a while)..."
dnf install -y "$ORACLE_DB_DOWNLOAD_LINK" >> "$LOG_FILE" 2>&1
log_success "Oracle Database 23ai Free package installed"

# Configure the database silently using ORACLE_PWD environment variable
log_info "Configuring Oracle Database (creating instance, this takes several minutes)..."
export ORACLE_PWD="${DB_PASSWORD}"
/etc/init.d/oracle-free-23ai configure >> "$LOG_FILE" 2>&1 <<EOF
$ORACLE_PWD
EOF
unset ORACLE_PWD
log_success "Oracle Database configured successfully"

# Set environment variables for oracle user (idempotent)
log_info "Setting environment variables for oracle user..."
ORACLE_BASHRC="/home/oracle/.bash_profile"
{
    grep -q "ORACLE_SID" "$ORACLE_BASHRC" || echo "export ORACLE_SID=${ORACLE_SID}"
    grep -q "ORACLE_HOME" "$ORACLE_BASHRC" || echo "export ORACLE_HOME=${ORACLE_HOME}"
    grep -q "ORACLE_HOME/bin" "$ORACLE_BASHRC" || echo 'export PATH=$PATH:$ORACLE_HOME/bin'
} >> "$ORACLE_BASHRC"
log_success "Environment variables set for oracle user"

# Enable database auto-start
log_info "Enabling Oracle Database service for auto-start..."
systemctl enable oracle-free-23ai >> "$LOG_FILE" 2>&1 || true
systemctl start oracle-free-23ai >> "$LOG_FILE" 2>&1 || true
log_success "Oracle Database service enabled"

# Verify the database is running
log_info "Verifying Oracle Database is running..."
run_sql_file <<'SQL' | tee -a "$LOG_FILE"
SELECT status FROM v$instance;
EXIT;
SQL
log_success "Oracle Database 23ai is running"

# =============================================================================
# 2. INSTALL ORACLE APEX
# =============================================================================

log_section "2/5 — Installing Oracle APEX"

# Download APEX
log_info "Downloading Oracle APEX..."
cd "$WORK_DIR"
if [[ ! -f "apex-latest.zip" ]]; then
    curl -# -o apex-latest.zip "$APEX_DOWNLOAD_URL" 2>> "$LOG_FILE"
fi
log_success "APEX downloaded"

# Extract APEX
log_info "Extracting APEX..."
unzip -qo apex-latest.zip -d "$WORK_DIR" >> "$LOG_FILE" 2>&1
rm -f apex-latest.zip
log_success "APEX extracted to ${WORK_DIR}/apex"

# Copy APEX directory to oracle home for installation
APEX_DIR="${WORK_DIR}/apex"
chown -R oracle:oinstall "$APEX_DIR"

# Install APEX into FREEPDB1
log_info "Installing APEX into ${DB_SERVICE} (this takes 20-45 minutes)..."
# apexins.sql must be run from the APEX directory
APEX_INSTALL_SQL=$(mktemp /tmp/apex_install_XXXXXX.sql)
cat > "$APEX_INSTALL_SQL" <<SQLEOF
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
@apexins.sql ${APEX_TABLESPACE} ${APEX_FILES_TABLESPACE} ${APEX_TEMP_TABLESPACE} ${APEX_IMAGES_PATH}
EXIT;
SQLEOF
chown oracle:oinstall "$APEX_INSTALL_SQL"
run_as_oracle "cd ${APEX_DIR} && sqlplus -s / as sysdba @${APEX_INSTALL_SQL}" >> "$LOG_FILE" 2>&1
rm -f "$APEX_INSTALL_SQL"
log_success "APEX installed successfully"

# Unlock and set password for APEX_PUBLIC_USER
log_info "Configuring APEX_PUBLIC_USER..."
run_sql_file <<SQLEOF >> "$LOG_FILE" 2>&1
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY ${APEX_PUBLIC_USER_PASSWORD};
EXIT;
SQLEOF
log_success "APEX_PUBLIC_USER configured"

# Create APEX ADMIN account
log_info "Creating APEX ADMIN account..."
run_sql_file <<SQLEOF >> "$LOG_FILE" 2>&1
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
BEGIN
    APEX_UTIL.set_security_group_id( 10 );
    APEX_UTIL.create_user(
        p_user_name       => '${APEX_ADMIN_USER}',
        p_email_address   => '${APEX_ADMIN_EMAIL}',
        p_web_password    => '${APEX_ADMIN_PASSWORD}',
        p_developer_privs => 'ADMIN'
    );
    APEX_UTIL.set_security_group_id( null );
    COMMIT;
END;
/
EXIT;
SQLEOF
log_success "APEX ADMIN account created"

# Configure APEX REST
log_info "Configuring APEX REST configuration..."
APEX_REST_SQL=$(mktemp /tmp/apex_rest_XXXXXX.sql)
cat > "$APEX_REST_SQL" <<SQLEOF
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
@apex_rest_config_core.sql ${APEX_PUBLIC_USER_PASSWORD} ${APEX_PUBLIC_USER_PASSWORD}
EXIT;
SQLEOF
chown oracle:oinstall "$APEX_REST_SQL"
run_as_oracle "cd ${APEX_DIR} && sqlplus -s / as sysdba @${APEX_REST_SQL}" >> "$LOG_FILE" 2>&1 || log_warn "apex_rest_config may have already been run — continuing"
rm -f "$APEX_REST_SQL"
log_success "APEX REST configured"

# Copy APEX images to permanent location
log_info "Copying APEX static images..."
mkdir -p "$(dirname "$ORDS_STATIC_IMAGES")"
cp -r "${APEX_DIR}/images" "$ORDS_STATIC_IMAGES"
chown -R oracle:oinstall "$ORDS_STATIC_IMAGES"
log_success "APEX images copied to ${ORDS_STATIC_IMAGES}"

# =============================================================================
# 3. INSTALL & CONFIGURE ORDS
# =============================================================================

log_section "3/5 — Installing ORDS"

# Install required packages
log_info "Installing Java 17 and dependencies..."
cat /dev/null > /etc/dnf/vars/ociregion 2>/dev/null || true
dnf install -y java-17-openjdk sudo nano >> "$LOG_FILE" 2>&1
log_success "Java 17 and dependencies installed"

# Verify Java
JAVA_VERSION=$(java -version 2>&1 | head -1)
log_info "Java version: ${JAVA_VERSION}"

# Configure sudoers for oracle user (idempotent)
log_info "Configuring sudoers for oracle user..."
if ! grep -q "oracle ALL=(ALL) NOPASSWD: ALL" /etc/sudoers 2>/dev/null; then
    echo "Defaults !lecture" >> /etc/sudoers
    echo "oracle ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    log_success "Sudoers configured for oracle user"
else
    log_info "Sudoers already configured — skipping"
fi

# Create ORDS directories
log_info "Creating ORDS directories..."
mkdir -p "$ORDS_CONFIG_DIR"
mkdir -p /home/oracle/logs
chmod -R 777 "$ORDS_CONFIG_DIR"
log_success "ORDS directories created"

# Add Oracle ORDS repo and install ORDS
log_info "Installing ORDS ${ORDS_VERSION}..."
yum-config-manager --add-repo=https://yum.oracle.com/repo/OracleLinux/OL8/oracle/software/x86_64 >> "$LOG_FILE" 2>&1 || \
    dnf config-manager --add-repo=https://yum.oracle.com/repo/OracleLinux/OL8/oracle/software/x86_64 >> "$LOG_FILE" 2>&1
dnf install -y "$ORDS_VERSION" --nogpgcheck >> "$LOG_FILE" 2>&1
log_success "ORDS installed"

# Install ORDS schema into the database (silent/non-interactive)
log_info "Installing ORDS schema into database (non-interactive)..."
ords --config "${ORDS_CONFIG_DIR}" install \
     --admin-user SYS \
     --db-hostname localhost \
     --db-port "${DB_PORT}" \
     --db-servicename "${DB_SERVICE}" \
     --feature-db-api true \
     --feature-rest-enabled-sql true \
     --feature-sdw true \
     --gateway-mode proxied \
     --gateway-user APEX_PUBLIC_USER \
     --log-folder /home/oracle/logs \
     --password-stdin <<ORDSPWD
${DB_PASSWORD}
${APEX_PUBLIC_USER_PASSWORD}
ORDSPWD
log_success "ORDS schema installed into database"

# Configure ORDS settings
log_info "Configuring ORDS settings..."
ords --config "${ORDS_CONFIG_DIR}" config set standalone.context.path "${ORDS_CONTEXT_PATH}"
ords --config "${ORDS_CONFIG_DIR}" config set standalone.doc.root "${ORDS_CONFIG_DIR}/global/doc_root"
ords --config "${ORDS_CONFIG_DIR}" config set standalone.http.port "${ORDS_HTTP_PORT}"
ords --config "${ORDS_CONFIG_DIR}" config set standalone.static.context.path /i
ords --config "${ORDS_CONFIG_DIR}" config set standalone.static.path "${ORDS_STATIC_IMAGES}/"
ords --config "${ORDS_CONFIG_DIR}" config set security.externalSessionTrustedOrigins "${ORDS_EXTERNAL_DOMAIN}"
ords --config "${ORDS_CONFIG_DIR}" config set security.httpsHeaderCheck "X-Forwarded-Proto: https"
ords --config "${ORDS_CONFIG_DIR}" config set security.forceHTTPS false
ords --config "${ORDS_CONFIG_DIR}" config set jdbc.InitialLimit "${ORDS_JDBC_INITIAL_LIMIT}"
ords --config "${ORDS_CONFIG_DIR}" config set jdbc.MaxLimit "${ORDS_JDBC_MAX_LIMIT}"
ords --config "${ORDS_CONFIG_DIR}" config set jdbc.MinLimit "${ORDS_JDBC_MIN_LIMIT}"
ords --config "${ORDS_CONFIG_DIR}" config delete db.serviceNameSuffix
log_success "ORDS settings configured"

# Fix MBEAN Warning in logging.properties
log_info "Fixing MBEAN warning in Java logging..."
LOGGING_PROPS=$(find / -name "logging.properties" -path "*/ords/*" 2>/dev/null | head -n 1)
if [[ -z "$LOGGING_PROPS" ]]; then
    LOGGING_PROPS=$(find / -name "logging.properties" 2>/dev/null | head -n 1)
fi
if [[ -n "$LOGGING_PROPS" ]]; then
    if ! grep -q "oracle.jdbc.level=OFF" "$LOGGING_PROPS" 2>/dev/null; then
        echo "oracle.jdbc.level=OFF" >> "$LOGGING_PROPS"
        log_success "MBEAN warning fix applied to ${LOGGING_PROPS}"
    else
        log_info "MBEAN fix already applied — skipping"
    fi
else
    log_warn "logging.properties not found — MBEAN fix skipped"
fi

# Generate ORDS WAR file for Tomcat deployment
log_info "Generating ORDS WAR file..."
ORDS_WAR_PATH="${WORK_DIR}/ords.war"
ords --config "${ORDS_CONFIG_DIR}" war "${ORDS_WAR_PATH}" >> "$LOG_FILE" 2>&1
log_success "ORDS WAR file generated at ${ORDS_WAR_PATH}"

# =============================================================================
# 4. INSTALL & CONFIGURE TOMCAT
# =============================================================================

log_section "4/5 — Installing Apache Tomcat ${TOMCAT_VERSION}"

# Download Tomcat
log_info "Downloading Tomcat ${TOMCAT_VERSION}..."
cd "$WORK_DIR"
if [[ ! -f "tomcat.zip" ]]; then
    curl -# -o tomcat.zip "$TOMCAT_DOWNLOAD_URL" 2>> "$LOG_FILE"
fi
log_success "Tomcat downloaded"

# Extract Tomcat
log_info "Extracting Tomcat..."
unzip -qo tomcat.zip -d "$WORK_DIR" >> "$LOG_FILE" 2>&1
rm -f tomcat.zip
log_success "Tomcat extracted"

# Move Tomcat to install directory
log_info "Installing Tomcat to ${TOMCAT_INSTALL_DIR}..."
if [[ -d "$TOMCAT_INSTALL_DIR" ]]; then
    log_warn "Tomcat directory already exists — removing old installation"
    rm -rf "$TOMCAT_INSTALL_DIR"
fi
mv "${WORK_DIR}/apache-tomcat-${TOMCAT_VERSION}" "$TOMCAT_INSTALL_DIR"
log_success "Tomcat installed to ${TOMCAT_INSTALL_DIR}"

# Create tomcat user and group
log_info "Creating tomcat user and group..."
if ! getent group "$TOMCAT_GROUP" > /dev/null 2>&1; then
    groupadd "$TOMCAT_GROUP"
fi
if ! id "$TOMCAT_USER" > /dev/null 2>&1; then
    useradd -r -g "$TOMCAT_GROUP" -d "$TOMCAT_INSTALL_DIR" -s /sbin/nologin "$TOMCAT_USER"
fi
log_success "Tomcat user/group created"

# Remove default webapps (security hardening)
log_info "Removing default Tomcat webapps (security hardening)..."
rm -rf "${TOMCAT_INSTALL_DIR}/webapps/docs"
rm -rf "${TOMCAT_INSTALL_DIR}/webapps/examples"
rm -rf "${TOMCAT_INSTALL_DIR}/webapps/host-manager"
# Keep ROOT and manager for now (manager may be useful for admin)
log_success "Default webapps removed"

# Deploy ORDS WAR
log_info "Deploying ORDS WAR to Tomcat..."
cp "${ORDS_WAR_PATH}" "${TOMCAT_INSTALL_DIR}/webapps/ords.war"
log_success "ORDS WAR deployed to ${TOMCAT_INSTALL_DIR}/webapps/ords.war"

# Deploy APEX static images as /i/ context
log_info "Deploying APEX static images to Tomcat..."
mkdir -p "${TOMCAT_INSTALL_DIR}/webapps/i"
cp -r "${ORDS_STATIC_IMAGES}/"* "${TOMCAT_INSTALL_DIR}/webapps/i/"
log_success "APEX images deployed as /i/ context"

# Create setenv.sh for ORDS configuration
log_info "Creating Tomcat setenv.sh for ORDS..."
cat > "${TOMCAT_INSTALL_DIR}/bin/setenv.sh" <<'SETENVEOF'
#!/bin/bash
# ORDS Configuration for Tomcat
SETENVEOF

# Append with variable expansion
cat >> "${TOMCAT_INSTALL_DIR}/bin/setenv.sh" <<SETENVEOF
export ORDS_CONFIG="${ORDS_CONFIG_DIR}"
export JAVA_OPTS="\${JAVA_OPTS} -Dconfig.url=\${ORDS_CONFIG} -Xms512M -Xmx1024M"
SETENVEOF

chmod +x "${TOMCAT_INSTALL_DIR}/bin/setenv.sh"
log_success "setenv.sh created"

# Make Tomcat scripts executable
chmod +x "${TOMCAT_INSTALL_DIR}/bin/"*.sh

# Set ownership and permissions
log_info "Setting Tomcat ownership and permissions..."
chown -R "${TOMCAT_USER}:${TOMCAT_GROUP}" "$TOMCAT_INSTALL_DIR"
chmod -R 750 "$TOMCAT_INSTALL_DIR"
# ORDS config needs to be readable by tomcat
chown -R "${TOMCAT_USER}:${TOMCAT_GROUP}" "$ORDS_CONFIG_DIR"
# APEX images need to be readable by tomcat
chown -R "${TOMCAT_USER}:${TOMCAT_GROUP}" "$ORDS_STATIC_IMAGES"
log_success "Ownership and permissions set"

# Create systemd service file
log_info "Creating Tomcat systemd service..."
JAVA_HOME_PATH=$(dirname $(dirname $(readlink -f $(which java))))

cat > /etc/systemd/system/tomcat.service <<SERVICEEOF
[Unit]
Description=Apache Tomcat ${TOMCAT_VERSION} — ORDS/APEX Application Server
After=network.target oracle-free-23ai.service
Wants=oracle-free-23ai.service

[Service]
Type=forking
User=${TOMCAT_USER}
Group=${TOMCAT_GROUP}

Environment=JAVA_HOME=${JAVA_HOME_PATH}
Environment=CATALINA_HOME=${TOMCAT_INSTALL_DIR}
Environment=CATALINA_BASE=${TOMCAT_INSTALL_DIR}
Environment=CATALINA_PID=${TOMCAT_INSTALL_DIR}/temp/tomcat.pid

ExecStart=${TOMCAT_INSTALL_DIR}/bin/startup.sh
ExecStop=${TOMCAT_INSTALL_DIR}/bin/shutdown.sh

RestartSec=10
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICEEOF

log_success "Systemd service file created"

# Enable and start Tomcat
log_info "Enabling and starting Tomcat service..."
systemctl daemon-reload
systemctl enable tomcat >> "$LOG_FILE" 2>&1
systemctl start tomcat >> "$LOG_FILE" 2>&1
log_success "Tomcat service started and enabled"

# =============================================================================
# 5. VERIFICATION & SUMMARY
# =============================================================================

log_section "5/5 — Verification"

# Wait for Tomcat to fully start
log_info "Waiting for Tomcat to initialize (30 seconds)..."
sleep 30

# Health check — ORDS
log_info "Checking ORDS health..."
ORDS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${ORDS_HTTP_PORT}/ords/" 2>/dev/null || echo "000")

if [[ "$ORDS_STATUS" == "200" || "$ORDS_STATUS" == "302" ]]; then
    log_success "ORDS is responding (HTTP ${ORDS_STATUS})"
elif [[ "$ORDS_STATUS" == "000" ]]; then
    log_warn "ORDS is not yet responding — Tomcat may still be starting"
    log_warn "Check manually: curl -I http://localhost:${ORDS_HTTP_PORT}/ords/"
    log_warn "Check Tomcat logs: ${TOMCAT_INSTALL_DIR}/logs/catalina.out"
else
    log_warn "ORDS returned HTTP ${ORDS_STATUS} — it may still be initializing"
fi

# Check Tomcat service status
log_info "Tomcat service status:"
systemctl is-active tomcat >> "$LOG_FILE" 2>&1 && log_success "Tomcat is active" || log_warn "Tomcat may not be running"

# Check Oracle DB service status
log_info "Oracle Database service status:"
systemctl is-active oracle-free-23ai >> "$LOG_FILE" 2>&1 && log_success "Oracle Database is active" || log_warn "Oracle Database may not be running"

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

# Cleanup work directory
log_info "Cleaning up work directory..."
rm -rf "$WORK_DIR"
log_success "Cleanup complete"

# Print summary
log_section "Installation Complete!"

SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Installation Summary                            ║${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}APEX URL:${NC}     http://${SERVER_IP}:${ORDS_HTTP_PORT}/ords/           ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Workspace:${NC}    INTERNAL                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Username:${NC}     ${APEX_ADMIN_USER}                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Password:${NC}     (as configured)                                ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Oracle SID:${NC}   ${ORACLE_SID}                                   ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Oracle Home:${NC}  ${ORACLE_HOME}   ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}PDB:${NC}          ${DB_SERVICE}                                   ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Tomcat:${NC}       ${TOMCAT_INSTALL_DIR}                            ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}ORDS Config:${NC}  ${ORDS_CONFIG_DIR}                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Log File:${NC}     ${LOG_FILE}                    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Time Elapsed:${NC} ${ELAPSED_MIN}m ${ELAPSED_SEC}s                  ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                               ${GREEN}║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

log_info "Full installation log: ${LOG_FILE}"
log_success "All done!"
