#!/bin/bash
# Clea-OS project navigation functions and aliases

alias SETUP_CLEA_DOCKER='docker_user="yoctouser"; docker_workdir="workdir"; docker run --rm -it \
    -v "${PWD}":/home/"${docker_user}"/"${docker_workdir}" \
    -v "${HOME}"/.gitconfig:/home/"${docker_user}"/.gitconfig:ro \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v "${HOME}"/.Xauthority:/home/"${docker_user}"/.Xauthority:rw \
    -v /etc/ssl/certs/:/etc/ssl/certs/:ro \
    --workdir=/home/"${docker_user}"/"${docker_workdir}" \
    secodocker/clea-os-builder:latest --username="${docker_user}"'

clea-init() {

    # Default branch
    local branch="${1:-scarthgap}"

    echo
    echo "Initializing CLEA OS repo with '${branch}' branch"
    echo "---------------------------------------------------"
    echo

    repo init -u https://git.seco.com/clea-os/seco-manifest.git -b "$branch" || return 1
    repo sync -j"$(nproc)" --fetch-submodules --no-clone-bundle
}


# ------------------------
# Show projects and navigate
# ------------------------
go-projects() {
    local index_file="$HOME/project-index"

    if [[ ! -f "$index_file" ]]; then
        echo "project-index file not found in $HOME"
        return 1
    fi

    mapfile -t raw_lines < "$index_file"

    if [[ ${#raw_lines[@]} -eq 0 ]]; then
        echo "No projects found."
        return 1
    fi

    echo "Available projects:"
    echo "-------------------"

    local -a paths
    local -a comments
    local -a exists_flags

    local i=0
    local display_index=1

    for line in "${raw_lines[@]}"; do
        [[ -z "$line" ]] && continue

        path="${line%%#*}"
        comment="${line#*#}"

        path="$(echo "$path" | xargs)"
        comment="$(echo "$comment" | xargs)"

        [[ -z "$path" ]] && continue

        paths[i]="$path"
        comments[i]="$comment"

        if [[ -d "$path" ]]; then
            exists_flags[i]=1
            status=""
        else
            exists_flags[i]=0
            status=" [MISSING]"
        fi

        printf "%2d) %-60s  # %s%s\n" \
            "$display_index" \
            "$path" \
            "$comment" \
            "$status"

        ((i++))
        ((display_index++))
    done

    echo
    read -p "Select project number (or press Enter to cancel): " selection
    [[ -z "$selection" ]] && return 0

    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        echo "Invalid selection."
        return 1
    fi

    if (( selection < 1 || selection > ${#paths[@]} )); then
        echo "Out of range."
        return 1
    fi

    local idx=$((selection-1))

    if [[ "${exists_flags[$idx]}" -eq 0 ]]; then
        echo "Cannot cd: Directory does not exist."
        return 1
    fi

    cd "${paths[$idx]}"
}

# ------------------------
# Go to source directories inside a build
# ------------------------
go-source() {

    # ---------------------------
    # Step 1: Find build dirs
    # ---------------------------
    mapfile -t builds < <(find . -maxdepth 1 -type d -name "build_*" | sort)

    echo "Available builds:"
    echo "-----------------"

    local i
    for i in "${!builds[@]}"; do
        printf "%2d) %s\n" $((i+1)) "${builds[$i]#./}"
    done
    # Add the new "go to workspace/sources" option
    echo " 0) Go to workspace/sources directly"

    echo
    read -p "Select build number (or Enter to cancel): " build_sel
    [[ -z "$build_sel" ]] && return 0

    local sources_dir

    if [[ "$build_sel" == "0" ]]; then
        # Direct jump to workspace/sources
        if [[ -d "workspace/sources" ]]; then
            cd "workspace/sources"
            return 0
        else
            echo "workspace/sources directory does not exist here."
            return 1
        fi
    fi

    if ! [[ "$build_sel" =~ ^[0-9]+$ ]] || \
       (( build_sel < 1 || build_sel > ${#builds[@]} )); then
        echo "Invalid selection."
        return 1
    fi

    local build_dir="${builds[$((build_sel-1))]}"
    sources_dir="$build_dir/workspace/sources"

    if [[ ! -d "$sources_dir" ]]; then
        echo "Sources directory not found: $sources_dir"
        return 1
    fi

    # ---------------------------
    # Step 2: List sources
    # ---------------------------
    mapfile -t sources < <(find "$sources_dir" -mindepth 1 -maxdepth 1 -type d | sort)

    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "No sources found in $sources_dir"
        return 1
    fi

    echo
    echo "Available sources:"
    echo "------------------"

    for i in "${!sources[@]}"; do
        printf "%2d) %s\n" $((i+1)) "$(basename "${sources[$i]}")"
    done

    echo
    read -p "Select source number (Enter to cancel): " src_sel
    [[ -z "$src_sel" ]] && return 0

    if ! [[ "$src_sel" =~ ^[0-9]+$ ]] || \
       (( src_sel < 1 || src_sel > ${#sources[@]} )); then
        echo "Invalid selection."
        return 1
    fi

    cd "${sources[$((src_sel-1))]}"
}


