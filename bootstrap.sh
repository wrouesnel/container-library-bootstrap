# See: https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
# Note: you can't refactor this out: its at the top of every script so the scripts can find their includes.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

function log() {
  echo "$*" 1>&2
}

function warn() {
  echo "$*" 1>&2
}

function fatal() {
  echo "$*" 1>&2
  exit 1
}

function must() {
    if ! "$0" "$@" ; then
        fatal "Failed: $0 $*"
    fi
    return 0
}

function check_exe() {
    local success=1
    for exe in "$@"; do
        if ! command -v "$exe" >/dev/null 2>&1; then
            success=0
            warn "$exe is not available in the current PATH"
        fi
    done
    if [ $success = 0 ]; then
        fatal "Some commands are not available. Check if they are installed and in the current system path."
    fi
    return 0
}

# atexit cmd ...  : run command at script exit
atexit () { eval _ae$_ae='("$@")'; _ae+=1; }
_runatexits () { while ((_ae--)); do eval '"${_ae'$_ae'[@]}"'; done; }
declare -i _ae=0; trap _runatexits EXIT

# check dependencies
check_exe \
    skopeo \
    jq \
    curl \
    git

opt_dryrun=0
opt_list=0
while [ -n "$1" ]; do
    arg="$1"
    case $arg in
        --list)
            opt_list=1
            ;;
        --dryrun|--dry-run|-n)
            opt_dryrun=1
            ;;
        --help)
                cat << EOF 1>&2
$0 [options] <target registry> [username [password]]

    --dryrun    Login to the registry but don't copy any images
    --list      Just list what would be copied
    --help      display this help

EOF
        exit 0
        ;;
        # Break loop and process position case
        *)
            break
        ;;
    esac
    shift
done

target_registry="$1"
shift

username="$1"
shift

password="$1"
shift

if [ "$opt_list" = 0 ]; then
    if [ -n "$username" ]; then
        log "Username specified: logging into registry: ${target_registry%%"/"*}"
        if [ -n "$password" ]; then
            must skopeo login --username "$username" --password-stdin "${target_registry%%"/"*}"
        else
            must skopeo login --username "$username" --password "$password" "${target_registry%%"/"*}"
        fi
    fi
fi

declare tmp_path
if ! tmp_path=$(mktemp -d) ; then
    fatal "Could not reate temp dir"
fi

atexit rmdir "$tmp_path"
atexit find "${tmp_path}" -mindepth 1 -delete

checkout_path="${tmp_path}/git"

# Acquire docker base images list
if ! git clone --depth 1 "https://github.com/docker-library/official-images" "${checkout_path}/docker-offical"; then
    fatal "Failed to clone the docker official images library"
fi

declare -a official_images

while read -r image_name; do
    official_images+=( "docker.io/library/${image_name}" )
done < <(ls -1 "${checkout_path}/docker-offical/library")

log "Retrieving image tags"
declare -a src_paths
for image_url in "${official_images[@]}"; do
    resp=""
    tags=""
    log "Get Tags: $image_url"
    if ! resp=$(skopeo list-tags "docker://${image_url}"); then
        warn "Error retrieving tags for ${image_url}"
    else
        if ! tags=$(jq -r '.Tags[]' <<< "$resp"); then
            warn "Error extracting tag list"
        fi
        while read -r tag; do
            src_paths+=( "docker://${image_url}:${tag}" )
        done <<< "$tags"
    fi
done

log "${#src_paths[@]} Source Images to Copy"
if [ $opt_list = 1 ]; then
    log "Images"
    for image_path in "${src_paths[@]}"; do
        echo "$image_path"
    done
fi

log "Copying images (this will take a while)"
for image_url in "${official_images[@]}"; do
    copy_cmd=( skopeo copy "${image_url}" "${target_registry}" )
    if [ opt_dryrun = 1 ]; then
        log "DRYRUN: " "${copy_cmd[0]}" "${copy_cmd[@]:1}"
    fi
    if ! "${copy_cmd[0]}" "${copy_cmd[@]:1}" ; then
        warn "Failed to copy ${image_url}"
    fi
done