#!/bin/bash

# --- FUNGSI-FUNGSI MESIN TRANSFER ---

# Mengurai output kemajuan dari rsync format JSON (lebih andal)
parse_rsync_progress_json() {
    local bytes_transferred=0
    local total_bytes=0 
    local current_speed="0B/s"
    local progress_percent="0%"
    local current_file="N/A" # TODO: Bisa diekstrak dari JSON jika diperlukan

    if [[ -f "${JOB_DIR}/total_size" ]]; then 
        total_bytes=$(cat "${JOB_DIR}/total_size")
    fi

    while IFS= read -r line; do
        # Hanya proses baris yang relevan (LOG_PROGRESS)
        if [[ "$line" != *"LOG_PROGRESS"* ]]; then continue; fi

        # Ekstrak nilai dari JSON menggunakan awk yang sangat spesifik
        local data=$(echo "$line" | awk -F', ' '{
            for(i=1; i<=NF; i++) {
                if($i ~ /"bytes":/) {
                    split($i, b, ":"); 
                    gsub(/"/, "", b[2]); 
                    printf "bytes=%s ", b[2]
                }
                if($i ~ /"percent":/) {
                    split($i, p, ":");
                    gsub(/"/, "", p[2]);
                    printf "percent=%s ", p[2]
                }
                if($i ~ /"speed":/) {
                    split($i, s, ":");
                    gsub(/"/, "", s[2]);
                    printf "speed=%s ", s[2]
                }
            }
            printf "\n"
        }')
        
        # Evaluasi output awk untuk menetapkan variabel shell
        eval "$data"

        bytes_transferred=${bytes:-0}
        progress_percent="${percent:-0}%"
        # Format kecepatan menggunakan human_size
        if [[ -n "$speed" ]] && [[ "$speed" -gt 0 ]]; then
             current_speed="$(human_size "$speed")/s"
        else
             current_speed="0B/s"
        fi
        
        echo "${bytes_transferred}|${total_bytes}|${progress_percent}|${current_speed}|${current_file}|IN_PROGRESS" > "${JOB_STATUS_FILE}"
    done

    echo "END|${total_bytes}|100%|N/A|N/A|COMPLETED" > "${JOB_STATUS_FILE}"
}


# Mengurai output kemajuan dari rsync dan menulis ke file status (fallback)
parse_rsync_progress() {
    local bytes_transferred=0
    local total_bytes=0 
    local current_speed="0B/s"
    local progress_percent="0%"
    local current_file="N/A"

    if [[ -f "${JOB_DIR}/total_size" ]]; then 
        total_bytes=$(cat "${JOB_DIR}/total_size")
    fi

    local re="^[[:space:]]*([0-9,]+)[[:space:]]+([0-9]+%)[[:space:]]+([0-9.]+[A-Za-z/]+)[[:space:]]+.*"
    while IFS= read -r line; do
        if [[ "${line}" =~ $re ]]; then
            bytes_transferred=$(echo "${BASH_REMATCH[1]}" | sed 's/,//g')
            progress_percent="${BASH_REMATCH[2]}"
            current_speed="${BASH_REMATCH[3]}"
        fi
        
        echo "${bytes_transferred}|${total_bytes}|${progress_percent}|${current_speed}|${current_file}|IN_PROGRESS" > "${JOB_STATUS_FILE}"
    done

    echo "END|${total_bytes}|100%|N/A|N/A|COMPLETED" > "${JOB_STATUS_FILE}"
}

# Wrapper untuk menjalankan perintah dengan logika coba lagi (tanpa eval)
run_rsync_retry() {
    local desc="$1"; shift
    local cmd_array=("$@")
    local max_retries=3
    local attempt=1
    
    while [[ $attempt -le $max_retries ]]; do
        if [[ $attempt -gt 1 ]]; then 
            echo "   ⚠️  Retry $attempt/$max_retries for: $desc..." | tee -a "$REPORT_TXT"
            sleep 3
        fi
        
        echo ">> Executing: $desc" | tee -a "$REPORT_TXT"

        # Pilih parser berdasarkan dukungan fitur
        if [[ "$ZTURBO_RSYNC_JSON_SUPPORT" == true ]]; then
            ( "${cmd_array[@]}" 2>&1; echo $? > "${JOB_DIR}/rsync_exit_status" ) | parse_rsync_progress_json &
        else
            ( "${cmd_array[@]}" 2>&1; echo $? > "${JOB_DIR}/rsync_exit_status" ) | parse_rsync_progress &
        fi
        local PARSER_PID=$!
        
        wait "${PARSER_PID}"
        
        status=$(cat "${JOB_DIR}/rsync_exit_status")
        rm -f "${JOB_DIR}/rsync_exit_status"
        
        if [[ $status -eq 0 ]]; then
            return 0
        fi
        
        echo "   ❌ Error (Code $status) on: $desc" | tee -a "$REPORT_TXT"
        ((attempt++))
    done
    return 1
}

# Fungsi eksekusi utama
main_execution() {
    local rsync_base_opts;
    local fpsync_base_opts;
    local prefix_array=();

    # Atur opsi dasar berdasarkan mode
    if [[ "$CURRENT_MODE" == "SAFE" ]]; then 
        prefix_array=(nice -n 10 ionice -c 2 -n 7)
        rsync_base_opts="-av --no-p --no-t --omit-dir-times --timeout=600 --partial-dir=.zturbo_partial"
    else 
        rsync_base_opts="-aW --no-p --no-t --omit-dir-times --inplace --sparse --no-compress --timeout=600"
        fpsync_base_opts="-lptgoD --numeric-ids --sparse --no-compress -W --inplace --timeout=60"
    fi

    # Tambahkan opsi progress bar berdasarkan dukungan fitur
    if [[ "$ZTURBO_RSYNC_JSON_SUPPORT" == true ]]; then
        rsync_base_opts+=" --info=progress2,stats2 --json"
        # fpsync tidak mendukung --json, jadi kita tetap pakai cara lama untuk itu
        fpsync_base_opts+=" --info=progress2"
    else
        rsync_base_opts+=" --info=progress2"
        fpsync_base_opts+=" --info=progress2"
    fi

    dynamic_governor &
    GOV_PID=$!
    EXIT_CODE=0

    if [[ ${#SELECTED_PATHS[@]} -gt 1 ]]; then
        if [[ "$CURRENT_MODE" == "SAFE" ]]; then
            echo ">> Multi-select detected (SAFE MODE - Sequential)."
            local cmd_array=( "${prefix_array[@]}" rsync $rsync_base_opts )
            cmd_array+=( "${SELECTED_PATHS[@]}" )
            cmd_array+=( "$DEST" )
            run_rsync_retry "Batch Transfer" "${cmd_array[@]}"
            EXIT_CODE=$?
        else
            echo ">> Multi-select detected (TURBO MODE - Hybrid)."
            local BG_PIDS=()
            
            wait_bg_files() {
                if [[ ${#BG_PIDS[@]} -gt 0 ]]; then
                    echo ">> Waiting for ${#BG_PIDS[@]} pending files..." | tee -a "$REPORT_TXT"
                    for pid in "${BG_PIDS[@]}"; do
                        wait "$pid" 2>/dev/null
                    done
                    BG_PIDS=()
                fi
            }

            for s in "${SELECTED_PATHS[@]}"; do
                local fname=$(basename "$s")
                
                if [[ -d "$s" ]]; then
                    wait_bg_files
                    # Catatan: fpsync tidak akan menggunakan parser JSON
                    local cmd_array=( "${prefix_array[@]}" fpsync -n "$THREADS" -f "$FILES_PER_JOB" -v -o "$fpsync_base_opts" "$s" "$DEST" )
                    run_rsync_retry "$fname" "${cmd_array[@]}"
                    [ $? -ne 0 ] && EXIT_CODE=1
                else
                    echo ">> [File] Background Start: $fname" | tee -a "$REPORT_TXT"
                    (
                        local cmd_array=( "${prefix_array[@]}" rsync $rsync_base_opts "$s" "$DEST" )
                        run_rsync_retry "$fname" "${cmd_array[@]}"
                    ) &
                    BG_PIDS+=($!)
                fi
            done
            wait_bg_files
        fi
    else
        local s="${SELECTED_PATHS[0]}"
        local fname=$(basename "$s")
        local cmd_array=()
        
        if [[ "$CURRENT_MODE" == "SAFE" ]]; then
            cmd_array=( "${prefix_array[@]}" rsync $rsync_base_opts "$s" "$DEST" )
        else
            if [[ -d "$s" ]]; then
                # Catatan: fpsync tidak akan menggunakan parser JSON
                cmd_array=( "${prefix_array[@]}" fpsync -n "$THREADS" -f "$FILES_PER_JOB" -v -o "$fpsync_base_opts" "$s" "$DEST" )
            else
                cmd_array=( "${prefix_array[@]}" rsync $rsync_base_opts "$s" "$DEST" )
            fi
        fi
        run_rsync_retry "$fname" "${cmd_array[@]}"
        EXIT_CODE=$?
    fi

    JOB_COMPLETED=true
}

# --- VERIFIKASI PASCA EKSEKUSI ---
post_execution_verification() {
    echo -e "\n${BOLD_YELLOW}🔎 VERIFYING DATA INTEGRITY...${NC}"

    calc_source() {
        local T_BYTES=0
        local T_FILES=0
        if [[ ${#SELECTED_PATHS[@]} -gt 0 ]]; then
            T_BYTES=$(du -scb "${SELECTED_PATHS[@]}" 2>/dev/null | tail -n 1 | cut -f1)
            [ -z "$T_BYTES" ] && T_BYTES=0
            # Optimize find to output just a dot per file and count bytes, avoids long strings
            T_FILES=$(find "${SELECTED_PATHS[@]}" -type f -printf '.' 2>/dev/null | wc -c)
        fi
        echo "$T_BYTES $T_FILES" > "/tmp/zturbo_src_$$"
    }

    # Optimasi: Hanya periksa item yang relevan di tujuan
    calc_dest() {
        local dest_root="$1"; shift
        local source_paths=("$@")
        local dest_items=()
        local T_BYTES=0
        local T_FILES=0

        # Jika tidak ada path sumber, tidak ada yang perlu dilakukan
        if [[ ${#source_paths[@]} -eq 0 ]]; then
            echo "0 0" > "/tmp/zturbo_dest_$$"; return
        fi
        
        # Bangun path tujuan dari basename sumber
        for src_path in "${source_paths[@]}"; do
            dest_items+=("$dest_root/$(basename "$src_path")")
        done

        # Periksa apakah path tujuan ada sebelum mencoba menghitung
        local existing_dest_items=()
        for item in "${dest_items[@]}"; do
            if [[ -e "$item" ]]; then
                existing_dest_items+=("\"$item\"")
            fi
        done
        
        if [[ ${#existing_dest_items[@]} -gt 0 ]]; then
            T_BYTES=$(du -scb ${existing_dest_items[*]} 2>/dev/null | tail -n 1 | cut -f1)
            [ -z "$T_BYTES" ] && T_BYTES=0
            T_FILES=$(find ${existing_dest_items[*]} -type f -printf '.' 2>/dev/null | wc -c)
        fi
        echo "$T_BYTES $T_FILES" > "/tmp/zturbo_dest_$$"
    }

    calc_source & local PID_SRC=$!
    # Panggil calc_dest dengan path tujuan dan array path sumber
    calc_dest "$DEST" "${SELECTED_PATHS[@]}" & local PID_DEST=$!
    wait $PID_SRC
    wait $PID_DEST

    read SRC_BYTES SRC_FILES < "/tmp/zturbo_src_$$"
    read DEST_BYTES DEST_FILES < "/tmp/zturbo_dest_$$"
    rm -f "/tmp/zturbo_src_$$" "/tmp/zturbo_dest_$$"

    local SIZE_STATUS="MISMATCH ❌"
    local FILE_STATUS="MISMATCH ❌"
    local FINAL_STATUS="FAILED ($EXIT_CODE)"

    if [[ "$SRC_BYTES" -eq "$DEST_BYTES" ]]; then SIZE_STATUS="MATCH ✅"; fi
    if [[ "$SRC_FILES" -eq "$DEST_FILES" ]]; then FILE_STATUS="MATCH ✅"; fi
    
    if [[ $EXIT_CODE -eq 0 ]]; then 
        if [[ "$SIZE_STATUS" == *"MATCH"* ]] && [[ "$FILE_STATUS" == *"MATCH"* ]]; then 
            FINAL_STATUS="SUCCESS ✅"
        else 
            FINAL_STATUS="WARNING ⚠️"
        fi
    fi

    END_TIME=$(date +%s)
    local FINISH_DATE=$(date)
    local DURATION=$((END_TIME - START_TIME))
    local DUR_FMT=$(format_duration $DURATION)
    local AVG_SPEED="0 B/s"
    if [[ $DURATION -gt 0 ]]; then
        local spd=$(( DEST_BYTES / DURATION ))
        AVG_SPEED="$(human_size $spd)/s"
    fi
    
    local H_SRC_BYTES=$(human_size $SRC_BYTES)
    local H_DEST_BYTES=$(human_size $DEST_BYTES)

    # Menambahkan spasi agar rapih (Tabular format manual)
    local PAD_SRC_B=$(printf "%-17s" "$H_SRC_BYTES")
    local PAD_DEST_B=$(printf "%-17s" "$H_DEST_BYTES")
    local PAD_SRC_F=$(printf "%-17s" "$SRC_FILES")
    local PAD_DEST_F=$(printf "%-17s" "$DEST_FILES")

    cat <<EOF >> "$REPORT_TXT"

================================================================
                  RECONCILIATION REPORT
================================================================
METRIC         SOURCE            DESTINATION       STATUS
----------------------------------------------------------------
Total Data     $PAD_SRC_B $PAD_DEST_B $SIZE_STATUS
Total Files    $PAD_SRC_F $PAD_DEST_F $FILE_STATUS
----------------------------------------------------------------
From           : ${SELECTED_PATHS[0]} $([ ${#SELECTED_PATHS[@]} -gt 1 ] && echo "(and $(( ${#SELECTED_PATHS[@]} - 1 )) others)")
To             : $DEST
----------------------------------------------------------------
Started        : $START_DATE
Finished       : $FINISH_DATE
Transfer Time  : $DUR_FMT
Average Speed  : $AVG_SPEED
Final Status   : $FINAL_STATUS
================================================================
EOF


    echo -e "\n✅ ${BOLD_GREEN}COMPLETED!${NC} Report saved to $REPORT_TXT"
    echo -e "Status: $FINAL_STATUS"
}
