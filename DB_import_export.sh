#!/bin/bash
# Author: Saurabh
# Purpose: MySQL export/import utility with multi-table include/exclude support

# Backup Directory
BACKUP_DIR="/Apachelog/DB_Backup"
mkdir -p "$BACKUP_DIR"

# Import Script Path
IMPORT_SCRIPT="/Apachelog/DB_Backup/mysql_import.sh"

# ────────────────────────────────
# Function: Show databases

show_databases() {
	mysql -h "$HOST" -u "$USER" --password="$PASS" --ssl-mode=REQUIRED -N -e \
    "SELECT table_schema AS \`Database\`,
        ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS \`Size (GB)\`
    FROM information_schema.tables
    GROUP BY table_schema
    ORDER BY SUM(data_length + index_length) DESC;" \
    2> >(grep -v "Using a password on the command line interface can be insecure." >&2)
}


# Function: Show tables in a database
show_tables() {
    mysql -h "$HOST" -u "$USER" -p"$PASS" --ssl-mode=REQUIRED -D "$1" \
    -e "SHOW TABLES;" 2>/dev/null | grep -v "Tables_in_"
}

# Timestamp helper
ts() { date '+%Y-%m-%d %H:%M:%S'; }

# ────────────────────────────────
echo "========== MySQL Export / Import Utility =========="
echo "1) Export Database/Table"
echo "2) Import Database"
echo "---------------------------------"
read -p "Enter your choice [1/2]: " ACTION

# ────────────────────────────────
# Import Section
if [[ "$ACTION" == "2" ]]; then
    echo ""
    echo "========== MySQL Import =========="
    read -p "Enter MySQL host: " HOST
    read -p "Enter MySQL username: " USER
    read -s -p "Enter MySQL password: " PASS
    echo ""
    echo "[$(ts)] ✅ Starting import..."
    bash "$IMPORT_SCRIPT" "$HOST" "$USER" "$PASS"
    exit 0
fi

# ────────────────────────────────
# Export Section
if [[ "$ACTION" == "1" ]]; then
    echo ""
    echo "========== MySQL Export =========="
    read -p "Enter MySQL host: " HOST
    read -p "Enter MySQL username: " USER
    read -s -p "Enter MySQL password: " PASS
    echo ""

    # Verify connection
    if ! mysql -h "$HOST" -u "$USER" -p"$PASS" --ssl-mode=REQUIRED -e "SELECT 1;" &>/dev/null; then
        echo "❌ Connection failed. Please check credentials."
        exit 1
    fi

    echo "✅ Connected to $HOST"
    DBS=$(show_databases)

    # Format into aligned table
    {
       echo "+------------------------------+-----------+"
       echo "| Database                     | Size (GB) |"
       echo "+------------------------------+-----------+"

    # Loop through each row and print formatted table
       while read -r db size; do
          printf "| %-28s | %9s |\n" "$db" "$size"
       done <<< "$DBS"

       echo "+------------------------------+-----------+"
    }


    read -p "Enter the database name to export: " DB
    echo ""
    echo "Select Export Mode:"
    echo "1) Export entire database"
    echo "2) Include specific tables only"
    echo "3) Exclude specific tables"
    read -p "Enter your choice [1/2/3]: " MODE

    TIMESTAMP=$(date +%F_%H%M%S)

    case "$MODE" in
        1)
            BASE_FILE="$BACKUP_DIR/${DB}_${TIMESTAMP}.sql"
            echo "[$(ts)] 📦 Exporting full database..."
            mysqldump -h "$HOST" -u "$USER" -p"$PASS" --ssl-mode=REQUIRED "$DB" > "$BASE_FILE"
            ;;
        2)
            echo "[$(ts)] 📋 Available tables in $DB:"
            show_tables "$DB"
            echo "---------------------------------"
            read -p "Enter table names to include (space-separated): " INCLUDE_TABLES

            # Detect if single or multiple tables
            TABLE_COUNT=$(echo "$INCLUDE_TABLES" | wc -w)
            if [[ "$TABLE_COUNT" -eq 1 ]]; then
                TABLE_NAME=$(echo "$INCLUDE_TABLES" | tr -d ' ')
                BASE_FILE="$BACKUP_DIR/${DB}_${TABLE_NAME}_${TIMESTAMP}.sql"
            elif [[ "$TABLE_COUNT" -eq 2 ]]; then
                # For exactly 2 tables, include both in file name
                TABLE1=$(echo "$INCLUDE_TABLES" | awk '{print $1}')
                TABLE2=$(echo "$INCLUDE_TABLES" | awk '{print $2}')
                BASE_FILE="$BACKUP_DIR/${DB}_${TABLE1}_${TABLE2}_${TIMESTAMP}.sql"
            else
                BASE_FILE="$BACKUP_DIR/${DB}_${TIMESTAMP}.sql"
            fi

            echo "[$(ts)] 📦 Exporting selected tables: $INCLUDE_TABLES"
            mysqldump -h "$HOST" -u "$USER" -p"$PASS" --ssl-mode=REQUIRED "$DB" $INCLUDE_TABLES > "$BASE_FILE"
            ;;
        3)
            BASE_FILE="$BACKUP_DIR/${DB}_exclude_${TIMESTAMP}.sql"
            echo "[$(ts)] 📋 Available tables in $DB:"
            show_tables "$DB"
            echo "---------------------------------"
            read -p "Enter table names to exclude (space-separated): " EXCLUDE_TABLES
            echo "[$(ts)] 🚫 Excluding tables: $EXCLUDE_TABLES"

            # Build exclusion args
            EXCLUDE_ARGS=()
            for T in $EXCLUDE_TABLES; do
                EXCLUDE_ARGS+=(--ignore-table="$DB.$T")
            done

            mysqldump -h "$HOST" -u "$USER" -p"$PASS" --ssl-mode=REQUIRED "${EXCLUDE_ARGS[@]}" "$DB" > "$BASE_FILE"
            ;;
        *)
            echo "❌ Invalid choice."
            exit 1
            ;;
    esac

    gzip "$BASE_FILE"
    FILE_NAME="${BASE_FILE}.gz"
    echo "[$(ts)] ✅ Export Completed → $FILE_NAME"
    exit 0
fi

# ────────────────────────────────
# Invalid Option
echo "❌ Invalid choice. Please select 1 or 2."
exit 1

