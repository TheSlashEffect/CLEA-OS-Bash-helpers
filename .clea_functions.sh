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
    if ! check_local_project_index; then
        return 1
    fi

    mapfile -t raw_lines < "$PROJECT_INDEX"

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


# Uses rsync to sync between artifact directory and flashing artifact location.
# Checks for projects in "remote_host", as well as local ones, according to
# the usual "project-index" structure.
clea-fetch-artifacts() {
    if ! check_local_artifact_index; then
        echo "ERROR: Local artifact index not found. Cannot operate without target directory"
        return 1
    fi

    if ! check_local_project_index; then
        echo "WARNING: Local project index not found, no local projects listed"
    fi

    local remote_user="xxx"
    local remote_host="xxx"

    local remote_project_file="\$HOME/project-index"
    local local_project_file="$PROJECT_INDEX"
    local local_artifact_file="$ARTIFACT_INDEX"

    local -a projects
    local -a project_locations   # "Remote" or "Local"

    # ----------------------------
    # 1️⃣ Load REMOTE project-index
    # ----------------------------
    mapfile -t remote_projects < <(
        ssh "$remote_user@$remote_host" \
        "grep -v '^[[:space:]]*$' $remote_project_file 2>/dev/null"
    )

    for line in "${remote_projects[@]}"; do
        projects+=("$line")
        project_locations+=("Remote")
    done

    # ----------------------------
    # 2️⃣ Load LOCAL project-index
    # ----------------------------
    if [[ -f "$local_project_file" ]]; then
        mapfile -t local_projects < <(
            grep -v '^[[:space:]]*$' "$local_project_file"
        )
        for line in "${local_projects[@]}"; do
            projects+=("$line")
            project_locations+=("Local")
        done
    fi

    if [[ ${#projects[@]} -eq 0 ]]; then
        echo "No projects found locally or remotely."
        return 1
    fi

    echo "Available Projects:"
    echo "-------------------"

    for i in "${!projects[@]}"; do
        path="${projects[$i]%%#*}"
        comment="${projects[$i]#*#}"
        location="${project_locations[$i]}"
        path="$(echo "$path" | xargs)"
        comment="$(echo "$comment" | xargs)"
        printf "%2d) (%s) %-60s  # %s\n" \
            $((i+1)) "$location" "$path" "$comment"
    done

    echo
    read -p "Select project: " proj_sel
    [[ -z "$proj_sel" ]] && return 0

    if ! [[ "$proj_sel" =~ ^[0-9]+$ ]] || \
       (( proj_sel < 1 || proj_sel > ${#projects[@]} )); then
        echo "Invalid selection."
        return 1
    fi

    idx=$((proj_sel-1))
    selected_line="${projects[$idx]}"
    location="${project_locations[$idx]}"

    project_path="${selected_line%%#*}"
    project_path="$(echo "$project_path" | xargs)"

    # ----------------------------
    # 3️⃣ Select Build
    # ----------------------------
    if [[ "$location" == "Remote" ]]; then
        mapfile -t builds < <(
            ssh "$remote_user@$remote_host" \
            "ls -d \"$project_path\"/build_* 2>/dev/null" | sort
        )
    else
        mapfile -t builds < <(
            ls -d "$project_path"/build_* 2>/dev/null | sort
        )
    fi

    if [[ ${#builds[@]} -eq 0 ]]; then
        echo "No builds found."
        return 1
    fi

    echo
    echo "Available Builds:"
    echo "-----------------"

    for i in "${!builds[@]}"; do
        printf "%2d) %s\n" $((i+1)) "$(basename "${builds[$i]}")"
    done

    echo
    read -p "Select build: " build_sel
    [[ -z "$build_sel" ]] && return 0

    if ! [[ "$build_sel" =~ ^[0-9]+$ ]] || \
       (( build_sel < 1 || build_sel > ${#builds[@]} )); then
        echo "Invalid selection."
        return 1
    fi

    selected_build="${builds[$((build_sel-1))]}"
    images_path="$selected_build/tmp/deploy/images"

    # ----------------------------
    # 4️⃣ Select Image Target
    # ----------------------------
    if [[ "$location" == "Remote" ]]; then
        mapfile -t images < <(
            ssh "$remote_user@$remote_host" \
            "ls -d \"$images_path\"/* 2>/dev/null" | sort
        )
    else
        mapfile -t images < <(
            ls -d "$images_path"/* 2>/dev/null | sort
        )
    fi

    if [[ ${#images[@]} -eq 0 ]]; then
        echo "No image directories found."
        return 1
    fi

    echo
    echo "Available Image Targets:"
    echo "------------------------"

    for i in "${!images[@]}"; do
        printf "%2d) %s\n" $((i+1)) "$(basename "${images[$i]}")"
    done

    echo
    read -p "Select image directory: " img_sel
    [[ -z "$img_sel" ]] && return 0

    if ! [[ "$img_sel" =~ ^[0-9]+$ ]] || \
       (( img_sel < 1 || img_sel > ${#images[@]} )); then
        echo "Invalid selection."
        return 1
    fi

    # 🔹 Go one level deeper into the specific image subdirectory
    if [[ "$location" == "Remote" ]]; then
        remote_image_dir="${images[$((img_sel-1))]}/seco-clea-os-image/"
    else
        remote_image_dir="${images[$((img_sel-1))]}/seco-clea-os-image/"
    fi

    # ----------------------------
    # 5️⃣ Select Local Artifact Destination
    # ----------------------------
    if [[ ! -f "$local_artifact_file" ]]; then
        echo "Local artifact-index not found."
        return 1
    fi

    mapfile -t artifacts < <(
        grep -v '^[[:space:]]*$' "$local_artifact_file"
    )

    echo
    echo "Available Local Artifact Destinations:"
    echo "--------------------------------------"

    for i in "${!artifacts[@]}"; do
        path="${artifacts[$i]%%#*}"
        comment="${artifacts[$i]#*#}"
        path="$(echo "$path" | xargs)"
        comment="$(echo "$comment" | xargs)"
        printf "%2d) %-60s  # %s\n" \
            $((i+1)) "$path" "$comment"
    done

    echo
    read -p "Select local destination: " art_sel
    [[ -z "$art_sel" ]] && return 0

    if ! [[ "$art_sel" =~ ^[0-9]+$ ]] || \
       (( art_sel < 1 || art_sel > ${#artifacts[@]} )); then
        echo "Invalid selection."
        return 1
    fi

    local_dest="${artifacts[$((art_sel-1))]%%#*}"
    local_dest="$(echo "$local_dest" | xargs)"
    mkdir -p "$local_dest"

    echo
    echo "Syncing:"
    if [[ "$location" == "Remote" ]]; then
        echo "  FROM: $remote_user@$remote_host:$remote_image_dir"
        echo "  TO  : $local_dest"
        echo
        rsync -avz --ignore-existing \
            "$remote_user@$remote_host:$remote_image_dir" \
            "$local_dest"
    else
        echo "  FROM: $remote_image_dir"
        echo "  TO  : $local_dest"
        echo
        rsync -av --ignore-existing \
            "$remote_image_dir" \
            "$local_dest"
    fi
}

: "${PROJECT_INDEX:=$HOME/project-index}"
: "${ARTIFACT_INDEX:=$HOME/artifact-index}"
readonly PROJECT_INDEX
readonly ARTIFACT_INDEX

# Index guards
check_local_project_index() {
    if [[ ! -f "$PROJECT_INDEX" ]]; then
        echo "ERROR: Project index missing: $PROJECT_INDEX"
        return 1
    fi
    return 0
}

check_local_artifact_index() {
    if [[ ! -f "$ARTIFACT_INDEX" ]]; then
        echo "ERROR: Artifact index missing: $ARTIFACT_INDEX"
        return 1
    fi
    return 0
}
