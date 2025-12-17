#!/bin/bash
# Author: Saurabh
# Purpose: Smart MySQL import tool (optimized + integrated)

echo "=== Database Import Tool ==="

# ────────────────────────────────
# Take credentials from args (HOST USER PASS)
TARGET_HOST="$1"
TARGET_USER="$2"
TARGET_PASS="$3"

# If not passed, prompt interactively (fallback)
if [[ -z "$TARGET_HOST" ]]; then
    read -p "Target MySQL Host: " TARGET_HOST
fi
if [[ -z "$TARGET_USER" ]]; then
    read -p "Target MySQL User: " TARGET_USER
fi
if [[ -z "$TARGET_PASS" ]]; then
    read -s -p "Target MySQL Password: " TARGET_PASS
    echo ""
fi

# ────────────────────────────────
echo ""
echo "Choose Import Mode:"
echo "1) Import directly from existing .sql/.sql.gz"
echo "2) Modify DB name (in-place copy) and then import"
read -p "Enter choice [1/2]: " MODE

read -p "Enter dump file (.sql or .sql.gz): " DUMP_FILE

if [[ ! -f "$DUMP_FILE" ]]; then
    echo "❌ File not found!"
    exit 1
fi

BACKUP_DIR="/Apachelog/DB_Backup"
mkdir -p "$BACKUP_DIR"

echo "[`date '+%Y-%m-%d %H:%M:%S'`] Detecting original database name..."

# ────────────────────────────────
# Detect original DB name (single pass)
if [[ "$DUMP_FILE" == *.gz ]]; then
    ORIGINAL_DB=$(zcat "$DUMP_FILE" | grep -m1 "^-- Host:" | awk '{print $NF}')
else
    ORIGINAL_DB=$(grep -m1 "^-- Host:" "$DUMP_FILE" | awk '{print $NF}')
fi

if [[ -z "$ORIGINAL_DB" ]]; then
    read -p "Could not auto-detect. Enter SOURCE DB Name: " ORIGINAL_DB
fi

echo "✅ Source Database detected: $ORIGINAL_DB"
echo ""

read -p "Enter NEW Target Database Name (will be created): " TARGET_DB

if [[ -z "$TARGET_DB" ]]; then
    echo "❌ Target DB name cannot be empty."
    exit 1
fi

# ────────────────────────────────
# Ensure target DB exists
echo "[`date '+%Y-%m-%d %H:%M:%S'`] Creating target database if not exists..."
mysql -h "$TARGET_HOST" -u "$TARGET_USER" -p"$TARGET_PASS" \
    -e "CREATE DATABASE IF NOT EXISTS \`$TARGET_DB\`;"

# ────────────────────────────────
# MODE 1 → Direct import (no DB rename)
if [[ "$MODE" == "1" ]]; then
    echo "[`date '+%Y-%m-%d %H:%M:%S'`] Importing dump directly into $TARGET_DB ..."
    if [[ "$DUMP_FILE" == *.gz ]]; then
        zcat "$DUMP_FILE" | mysql -h "$TARGET_HOST" -u "$TARGET_USER" -p"$TARGET_PASS" "$TARGET_DB"
    else
        mysql -h "$TARGET_HOST" -u "$TARGET_USER" -p"$TARGET_PASS" "$TARGET_DB" < "$DUMP_FILE"
    fi
    echo "✅ Direct Import Completed Successfully."
    exit 0
fi

# ────────────────────────────────
# ────────────────────────────────
# MODE 2 → Replace DB Name and comment GTID (single read, create new file)
echo "[`date '+%Y-%m-%d %H:%M:%S'`] Preparing modified working copy..."

BASENAME="$(basename "$DUMP_FILE" | sed -E 's/(\.gz)$//')"   # strip only .gz
TEMP_FILE="$BACKUP_DIR/modified_${BASENAME%.sql}_$(date +%F_%H%M%S).sql"
FINAL_FILE="$TEMP_FILE"

# Modify and produce the uncompressed SQL
if [[ "$DUMP_FILE" == *.gz ]]; then
    zcat "$DUMP_FILE" \
    | sed -e "s/\`$ORIGINAL_DB\`/\`$TARGET_DB\`/g" \
          -e "s/^SET @@GLOBAL.GTID_PURGED/# &/" \
          -e "s/^SET @@SESSION.SQL_LOG_BIN/# &/" \
    > "$TEMP_FILE"
else
    sed -e "s/\`$ORIGINAL_DB\`/\`$TARGET_DB\`/g" \
        -e "s/^SET @@GLOBAL.GTID_PURGED/# &/" \
        -e "s/^SET @@SESSION.SQL_LOG_BIN/# &/" \
        "$DUMP_FILE" > "$TEMP_FILE"
fi

# Compress the file if original was gzipped
if [[ "$DUMP_FILE" == *.gz ]]; then
    gzip -f "$TEMP_FILE"
    FINAL_FILE="${TEMP_FILE}.gz"
fi

echo "[`date '+%Y-%m-%d %H:%M:%S'`] Importing modified dump into $TARGET_DB ..."
if [[ "$FINAL_FILE" == *.gz ]]; then
    zcat "$FINAL_FILE" | mysql -h "$TARGET_HOST" -u "$TARGET_USER" -p"$TARGET_PASS" "$TARGET_DB"
else
    mysql -h "$TARGET_HOST" -u "$TARGET_USER" -p"$TARGET_PASS" "$TARGET_DB" < "$FINAL_FILE"
fi

echo ""
echo "✅ DB Name Replace Import Completed Successfully!"
echo "🎯 Imported into: $TARGET_DB"
echo "💾 Modified SQL saved at: $FINAL_FILE"
exit 0