#!/bin/bash

# --- FUNGSI-FUNGSI TERKAIT ANTARMUKA PENGGUNA (UI) ---

# Menampilkan header utama
print_header() {
    clear
    MY_IP=$(hostname -I | awk '{print $1}')
    echo -e "${BOLD_GREEN}==========================================${NC}"
    echo -e "${BOLD_GREEN} ZTURBO V1.3.5 (MODULAR)${NC}"
    echo -e "${BOLD_GREEN}==========================================${NC}"
    echo -e "👤 USER: ${BOLD_YELLOW}$REAL_USER${NC} | 🌐 IP: ${BOLD_MAGENTA}$MY_IP${NC} | 💾 MODE: $CURRENT_MODE"
    echo -e "------------------------------------------"
}

# Menampilkan footer menu
show_footer() {
    echo -e "${K}"
    echo -e "${C}═════════════════════════════════════════════════════════════════════════════════${NC}${K}"
    echo -e "$1${K}"
    echo -e "${C}═════════════════════════════════════════════════════════════════════════════════${NC}${K}"
    printf "\033[?25h" # Show Cursor for Input
    echo -n " 👉 INPUT > "
}

# Modul untuk memilih sumber
select_source() {
    # Inisialisasi sumber daya browser
    mkdir -p "$BROWSER_DIR"
    local PREV_NAV_PATH=""
    local -A SIZE_CACHE

    # Fungsi pembersihan khusus untuk browser. Dipanggil saat fungsi `select_source` selesai.
    cleanup_browser() {
        if [[ -n "$CURRENT_SIZE_CALC_PID" ]]; then
            kill "$CURRENT_SIZE_CALC_PID" 2>/dev/null
            CURRENT_SIZE_CALC_PID=""
        fi
    }
    trap 'cleanup_browser; trap - RETURN' RETURN

    while true; do
        print_header
        echo -e "${BOLD_YELLOW}[ STEP 1 ] SELECT SOURCE LOCATION${NC}"
        
        mapfile -t mounts < <(mount | grep -E "type cifs|type nfs|type gpfs|type smb|on /mnt|on /media" | awk '{print $3 "|" $1}')
        echo -e " [0] 🏠 HOME DIRECTORY ($HOME)"
        echo -e " [1] 🌳 ROOT DIRECTORY (/)"
        i=2
        for line in "${mounts[@]}"; do
            path=$(echo "$line" | cut -d'|' -f1)
            src=$(echo "$line" | cut -d'|' -f2)
            echo -e " [$i] 📂 ${BOLD_MAGENTA}$path${NC}"
            echo -e "     └─ 🔗 Source: ${GREY}$src${NC}"
            ((i++))
        done
        show_footer "[#] Select | [Q] Quit"
        read -e pil || exit 1
        
        if [[ "${pil^^}" == "Q" ]]; then exit 0; fi
        
        if [[ "$pil" == "0" ]]; then NAV_PATH="$HOME"
        elif [[ "$pil" == "1" ]]; then NAV_PATH="/"
        elif [[ "$pil" =~ ^[0-9]+$ ]] && [[ "$pil" -lt "$i" ]]; then
             idx=$((pil-2)); l="${mounts[$idx]}"; NAV_PATH=$(echo "$l" | cut -d'|' -f1)
        else 
             echo "Invalid Choice!"; sleep 1; continue
        fi

        MOUNT_ROOT="$NAV_PATH"
        BREAK_SRC=false; PAGE=1; PER_PAGE=15
        
        while true; do
            # --- Logika Kalkulasi Ukuran Asinkron ---
            if [[ "$NAV_PATH" != "$PREV_NAV_PATH" ]]; then
                cleanup_browser # Bunuh proses lama jika ada
                PREV_NAV_PATH="$NAV_PATH"
                
                # Gunakan hash dari path sebagai nama file cache yang aman
                CACHE_FILE="$BROWSER_DIR/$(echo "$NAV_PATH" | md5sum | awk '{print $1}').cache"
                # Hapus cache lama jika ada dan buat yang baru
                rm -f "$CACHE_FILE" && touch "$CACHE_FILE"

                # Jalankan kalkulasi di latar belakang
                calculate_sizes_background "$NAV_PATH" "$CACHE_FILE" &
                CURRENT_SIZE_CALC_PID=$!
                
                # Reset cache di memori
                declare -A SIZE_CACHE
            fi
            
            # Baca pembaruan dari file cache ke dalam cache memori (associative array)
            # Ini sangat cepat karena file ada di RAM-disk
            while IFS=: read -r path size; do
                SIZE_CACHE["$path"]="$size"
            done < "$CACHE_FILE"

            # --- Tampilan UI ---
            print_header
            echo -e "${BOLD_YELLOW}[ BROWSE SOURCE ]${NC} ${BOLD_WHITE}$NAV_PATH${NC}"
            
            SEL_COUNT=${#SELECTED_MAP[@]}
            if [[ $SEL_COUNT -gt 0 ]]; then
                echo -e "${BOLD_GREEN}✅ Selected Items: $SEL_COUNT${NC} (Type 'D' to Finalize)"
            else
                echo -e "${GREY}   No items selected yet.${NC}"
            fi

            mapfile -t contents < <(\ls -1 -A --group-directories-first --color=never "$NAV_PATH" 2>/dev/null)
            total_items=${#contents[@]}
            
            total_pages=$(( (total_items + PER_PAGE - 1) / PER_PAGE ))
            [ $total_pages -eq 0 ] && total_pages=1
            [ $PAGE -gt $total_pages ] && PAGE=$total_pages
            [ $PAGE -lt 1 ] && PAGE=1
            start_idx=$(( (PAGE - 1) * PER_PAGE ))
            
            echo -e " ----------------------------------------"
            echo -e " PAGE $PAGE of $total_pages | Total Items: $total_items"
            echo -e " ----------------------------------------"
            
            if [[ "$PAGE" -eq 1 ]]; then
                 echo -e " [0] ✅ DONE / SELECT CURRENT FOLDER"
            fi

            for (( i=0; i<PER_PAGE; i++ )); do
                idx=$(( start_idx + i ))
                if [[ $idx -ge $total_items ]]; then break; fi
                
                item="${contents[$idx]}"
                fp="${NAV_PATH%/}/$item"
                
                if [[ -n "${SELECTED_MAP["$fp"]}" ]]; then
                    MARK="[${BOLD_GREEN}*${NC}]"
                else
                    MARK="[ ]"
                fi
                
                # Ambil ukuran dari cache, jika tidak ada, gunakan '?'
                item_size=${SIZE_CACHE["$fp"]:-?}

                rel_num=$(( i + 1 ))
                
                if [[ -d "$fp" ]]; then
                    printf " %s [%2d] 📁 ${BOLD_CYAN}%-30s${NC} ${BOLD_YELLOW}(%s)${NC}\n" "$MARK" "$rel_num" "$item/" "$item_size"
                else
                    printf " %s [%2d] 📄 %-30s ${GREY}(%s)${NC}\n" "$MARK" "$rel_num" "$item" "$item_size"
                fi
            done
            
            # --- Penanganan Input ---
            NAV_MENU=""
            if [[ $PAGE -lt $total_pages ]]; then NAV_MENU+="[N] Next | "; fi
            if [[ $PAGE -gt 1 ]]; then NAV_MENU+="[P] Prev | "; fi
            if [[ "$NAV_PATH" == "$MOUNT_ROOT" ]] || [[ "$NAV_PATH" == "/" ]]; then BACK_MSG="Main Menu"; else BACK_MSG="Up (..)"; fi
            
            show_footer "${NAV_MENU}[#] Enter/Toggle | [S #] Sel | [A] All | [C] Clear | [D] Done | [B] $BACK_MSG"
            read -e inp || exit 1
            
            INP_UP="${inp^^}"
            
            if [[ "$INP_UP" == "Q" ]]; then exit 0; fi
            if [[ "$INP_UP" == "D" ]] || [[ "$inp" == "0" ]]; then
                if [[ ${#SELECTED_MAP[@]} -eq 0 ]]; then
                     SELECTED_MAP["$NAV_PATH"]=1
                fi
                BREAK_SRC=true; break
            fi
            
            if [[ "$INP_UP" == "B" ]]; then
                if [[ "$NAV_PATH" == "$MOUNT_ROOT" ]] || [[ "$NAV_PATH" == "/" ]]; then break
                else NAV_PATH=$(dirname "$NAV_PATH"); PAGE=1; continue; fi
            fi
            
            if [[ "$INP_UP" == "N" ]]; then
                if [[ $PAGE -lt $total_pages ]]; then PAGE=$((PAGE+1)); fi; continue
            fi
            if [[ "$INP_UP" == "P" ]]; then
                if [[ $PAGE -gt 1 ]]; then PAGE=$((PAGE-1)); fi; continue
            fi
            
            if [[ "$INP_UP" == "A" ]]; then
                 for item in "${contents[@]}"; do
                    full_p="${NAV_PATH%/}/$item"
                    SELECTED_MAP["$full_p"]=1
                 done
                 continue
            fi
            
            if [[ "$INP_UP" == "C" ]]; then
                SELECTED_MAP=()
                continue
            fi

            if [[ "$inp" =~ ^[sS][[:space:]]*([0-9]+)$ ]]; then
                num="${BASH_REMATCH[1]}"
                if [[ "$num" -gt 0 ]] && [[ "$num" -le "$PER_PAGE" ]]; then
                     abs_idx=$(( start_idx + num - 1 ))
                     if [[ $abs_idx -lt $total_items ]]; then
                         item="${contents[$abs_idx]}"
                         target="${NAV_PATH%/}/$item"
                         
                         if [[ -n "${SELECTED_MAP["$target"]}" ]]; then
                             unset SELECTED_MAP["$target"]
                         else
                             SELECTED_MAP["$target"]=1
                         fi
                     fi
                fi
                continue
            fi
            
            if [[ "$inp" =~ ^[0-9]+$ ]]; then
                num=$inp
                if [[ "$num" -gt 0 ]] && [[ "$num" -le "$PER_PAGE" ]]; then
                    abs_idx=$(( start_idx + num - 1 ))
                    if [[ $abs_idx -lt $total_items ]]; then
                        sel="${contents[$abs_idx]}"
                        target="${NAV_PATH%/}/$sel"
                        
                        if [[ -d "$target" ]]; then
                            NAV_PATH="$target"
                            PAGE=1
                        else
                            if [[ -n "${SELECTED_MAP["$target"]}" ]]; then
                                unset SELECTED_MAP["$target"]
                            else
                                SELECTED_MAP["$target"]=1
                            fi
                        fi
                    fi
                fi
            fi
        done
        
        if [[ "$BREAK_SRC" == true ]]; then 
            SELECTED_PATHS=()
            for key in "${!SELECTED_MAP[@]}"; do
                SELECTED_PATHS+=("$key")
            done
            # Pastikan pembersihan terakhir terjadi sebelum kembali
            cleanup_browser
            return 0
        fi
    done
}

# Modul untuk memilih tujuan
select_dest() {
    while true; do
        print_header
        echo -e "${BOLD_YELLOW}[ STEP 2 ] SELECT DESTINATION${NC}"
        count=${#SELECTED_PATHS[@]}
        if [[ $count -gt 0 ]]; then
             echo -e "Source: ${BOLD_CYAN}${SELECTED_PATHS[0]}${NC} $([ $count -gt 1 ] && echo "+ $((count-1)) more")"
        fi
        echo -e "------------------------------------------"
        
        mapfile -t mounts < <(mount | grep -E "type cifs|type nfs|type gpfs|type smb|on /mnt|on /media" | awk '{print $3 "|" $1}')
        echo -e " [0] 🏠 HOME DIR ($HOME)"
        echo -e " [1] 🌳 ROOT DIR (/)"
        i=2
        for line in "${mounts[@]}"; do
            path=$(echo "$line" | cut -d'|' -f1)
            src=$(echo "$line" | cut -d'|' -f2)
            echo -e " [$i] 📂 ${BOLD_MAGENTA}$path${NC}"
            echo -e "     └─ 🔗 Source: ${GREY}$src${NC}"
            ((i++))
        done
        show_footer "[#] Select | [R] Refresh | [B] Back"
        read -e pil || exit 1
        
        if [[ "${pil^^}" == "Q" ]]; then exit 0; fi
        if [[ "${pil^^}" == "B" ]]; then return 1; fi
        if [[ "${pil^^}" == "R" ]]; then continue; fi
        
        if [[ "$pil" == "0" ]]; then NAV_PATH="$HOME"
        elif [[ "$pil" == "1" ]]; then NAV_PATH="/"
        elif [[ "$pil" =~ ^[0-9]+$ ]] && [[ "$pil" -lt "$i" ]]; then 
            idx=$((pil-2)); l="${mounts[$idx]}"; NAV_PATH=$(echo "$l" | cut -d'|' -f1)
        else echo "Invalid!"; sleep 1; continue; fi

        MOUNT_ROOT="$NAV_PATH"
        BREAK_DEST=false
        PAGE=1
        PER_PAGE=15

        while true; do
            print_header
            echo -e "${BOLD_YELLOW}[ BROWSE DESTINATION ]${NC} ${BOLD_WHITE}$NAV_PATH${NC}"
            
            mapfile -t contents < <(\ls -1 -A --group-directories-first --color=never "$NAV_PATH" 2>/dev/null)
            total_items=${#contents[@]}

            total_pages=$(( (total_items + PER_PAGE - 1) / PER_PAGE ))
            [ $total_pages -eq 0 ] && total_pages=1
            [ $PAGE -gt $total_pages ] && PAGE=$total_pages
            [ $PAGE -lt 1 ] && PAGE=1
            
            start_idx=$(( (PAGE - 1) * PER_PAGE ))

            echo -e " ----------------------------------------"
            echo -e " PAGE $PAGE of $total_pages | [0] ✅ SELECT CURRENT FOLDER"
            echo -e " ----------------------------------------"

            for (( i=0; i<PER_PAGE; i++ )); do
                idx=$(( start_idx + i ))
                if [[ $idx -ge $total_items ]]; then break; fi
                
                item="${contents[$idx]}"
                fp="${NAV_PATH%/}/$item"
                rel_num=$(( i + 1 ))

                if [[ -d "$fp" ]]; then 
                    echo -e " [$rel_num] 📁 ${BOLD_CYAN}$item/${NC}"
                else
                    echo -e " [$rel_num] 📄 $item"
                fi
            done
            
            NAV_MENU=""
            if [[ $PAGE -lt $total_pages ]]; then NAV_MENU+="[N] Next | "; fi
            if [[ $PAGE -gt 1 ]]; then NAV_MENU+="[P] Prev | "; fi
            if [[ "$NAV_PATH" == "$MOUNT_ROOT" ]] || [[ "$NAV_PATH" == "/" ]]; then BACK_MSG="Main Menu"; else BACK_MSG="Up (..)"; fi
            
            show_footer "${NAV_MENU}[#] Enter | [MK] New Folder | [0] Select | [B] $BACK_MSG"
            read -e inp || exit 1
            INP_UP="${inp^^}"
            
            if [[ "$INP_UP" == "B" ]]; then 
                if [[ "$NAV_PATH" == "$MOUNT_ROOT" ]] || [[ "$NAV_PATH" == "/" ]]; then break; else NAV_PATH=$(dirname "$NAV_PATH"); PAGE=1; continue; fi
            fi
            
            if [[ "$inp" == "0" ]]; then DEST_ROOT="$NAV_PATH"; BREAK_DEST=true; break; fi
            if [[ "$INP_UP" == "MK" ]]; then read -e -p "New Folder Name: " new_f; mkdir -p "$NAV_PATH/$new_f"; continue; fi
            
            if [[ "$INP_UP" == "N" ]]; then if [[ $PAGE -lt $total_pages ]]; then PAGE=$((PAGE+1)); fi; continue; fi
            if [[ "$INP_UP" == "P" ]]; then if [[ $PAGE -gt 1 ]]; then PAGE=$((PAGE-1)); fi; continue; fi

            if [[ "$inp" =~ ^[0-9]+$ ]]; then
                num=$inp
                if [[ "$num" -gt 0 ]] && [[ "$num" -le "$PER_PAGE" ]]; then
                    abs_idx=$(( start_idx + num - 1 ))
                    if [[ $abs_idx -lt $total_items ]]; then
                        sel="${contents[$abs_idx]}"
                        target="${NAV_PATH%/}/$sel"
                        if [[ -d "$target" ]]; then NAV_PATH="$target"; PAGE=1
                        else echo -e "${BOLD_RED}Target is not a directory.${NC}"; sleep 1; fi
                    fi
                fi
            fi
        done
        if [[ "$BREAK_DEST" == true ]]; then return 0; fi
    done
}
