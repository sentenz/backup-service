#! /bin/bash
#
# Handles the creation/update/deletion of git subtree entries.

readonly NO_ERROR=0
readonly ERROR_ARGUMENTS_MISSING=1
readonly ERROR_SOURCE_FILE_NOT_EXIST=2
readonly ERROR_ADDING_GIT_SUBTREE=3
readonly ERROR_ADDING_FILE_TO_GIT_INDEX=4
readonly ERROR_COMMITING_GIT_INDEX=5
readonly ERROR_PUSH_GIT_COMMITS=6
readonly ERROR_UNSTAGED_CHANGES_FOUND=7
readonly ERROR_NOT_COMMITTED_CHANGES_FOUND=8
readonly ERROR_NOT_EVERYTHING_PUSHED=9
readonly ERROR_REMOVING_GIT_FOLDER=10
readonly GIT_SUBTREE_SOURCE_FILE=".resource/.subtreerc.csv"
readonly GIT_SUBTREE_NOTICE_FILE="subtree-update-notice.csv"
readonly COMMIT_MESSAGE_ADD="refactor: add git subtree entry: "
readonly COMMIT_MESSAGE_DELETE="refactor: delete git subtree entry: "
readonly SEPERATOR_LINE="-------------------"
readonly SUBTREE_WAS_UPDATED=0
readonly SUBTREE_WAS_NOT_UPDATED=1
readonly EXIST=0
readonly NOT_EXIST=1
ACTIVATE_PUSH=false
ACTIVATE_OUTPUT_FILE=false

main() {
    # Local variables
    local action=""
    local folder_path=""
    local url=""
    local branch=""
    local action_returncode=${NO_ERROR}

    # Get user options
    while getopts ':aurhlopf:g:b:' flag; do
        case "${flag}" in
        a) action="a" ;;
        b) branch="${OPTARG}" ;;
        f) folder_path="${OPTARG}" ;;
        g) url="${OPTARG}" ;;
        h)
            usage
            exit ${NO_ERROR}
            ;;
        l)
            list_all_source_file_entries
            exit ${NO_ERROR}
            ;;
        o) ACTIVATE_OUTPUT_FILE=true ;;
        p) ACTIVATE_PUSH=true ;;
        u) action="u" ;;
        r) action="r" ;;
        *) echo "Unexpected option ${flag}" ;;
        esac
    done

    # Ensure that the variable can now no longer be changed.
    readonly ACTIVATE_PUSH
    readonly ACTIVATE_OUTPUT_FILE

    check_for_changes
    action_returncode=${?}
    if [[ ${action_returncode} -ne ${NO_ERROR} ]]; then
        echo "Local working tree is not clean. Please commit or delete all changes."
        echo "${SEPERATOR_LINE}"
        usage
        exit ${action_returncode}
    fi

    if [[ ${action} == "a" ]]; then
        echo "Add git subtree entry"
        action_add_subtree "${folder_path}" "${url}" "${branch}"
        action_returncode=${?}
    elif [[ ${action} == "u" ]]; then
        echo "Update all git subtree entries"
        action_update_all_subtrees
        action_returncode=${?}
    elif [[ ${action} == "r" ]]; then
        echo "Remove git subtree entry"
        action_remove_subtree "${folder_path}"
        action_returncode=${?}
    else
        echo "Error, no action defined."
        echo "${SEPERATOR_LINE}"
        usage
        action_returncode=${ERROR_ARGUMENTS_MISSING}
    fi

    if ! check_everything_pushed && [[ ${ACTIVATE_PUSH} == false ]]; then
        echo -e "\n!!! Attention, automatic git push has not been activated !!!"
        echo -e "Non-pushed commits exist. Please push manually.\n"
    fi

    exit ${action_returncode}
}

function usage() {
    echo "usage: $0 [-action options] [-setting options]"
    echo -e "\nThis script forks external git repositories as" \
        "a submodule into this repository."
    echo -e "\nFor each existing repository that is updated" \
        "during the 'update' action, an entry is created" \
        "in the file '${GIT_SUBTREE_NOTICE_FILE}', if option -o is choosen."
    echo -e "\nAttention. The local working branch must not contain" \
        "any non-indexed or non-committed changes. "
    echo -e "\nAction options:"
    echo "  -h      display usage"
    echo "  -l      list all git subtree entries"
    echo "  -a      add git subtree entry (need argument -f -g -b)"
    echo "  -u      update all git subtree entries"
    echo "  -r      remove git subtree entry (need argument -f)"
    echo -e "\nSetting options:"
    echo "  -f      local folder path where the git subtree should be stored"
    echo "  -g      git url of origin repository which should be forked"
    echo "  -b      branch of origin repository which should be forked"
    echo "  -o      enable writing file '${GIT_SUBTREE_NOTICE_FILE}'" \
        "if updates are done"
    echo "  -p      enable automatic git push"

}

function action_add_subtree() {
    local folder_path=${1}
    local url=${2}
    local branch=${3}
    local commit_message="${COMMIT_MESSAGE_ADD} ${folder_path}, ${url}, ${branch}"

    if [[ -z "${folder_path}" ]] || [[ -z "${url}" ]] || [[ -z "${branch}" ]]; then
        echo "Error, arguments missing!"
        echo "Folder: ${folder_path}"
        echo "Git url: ${url}"
        echo "Branch: ${branch}"
        echo "${SEPERATOR_LINE}"
        usage
        return ${ERROR_ARGUMENTS_MISSING}
    fi

    if ! exist_file "${GIT_SUBTREE_SOURCE_FILE}"; then
        echo "Error, source file '${GIT_SUBTREE_SOURCE_FILE}' not found!"
        return ${ERROR_SOURCE_FILE_NOT_EXIST}
    fi

    if ! add_git_subtree "${folder_path}" "${url}" "${branch}"; then
        echo "Error, git subtree add failed!"
        return ${ERROR_ADDING_GIT_SUBTREE}
    fi

    add_new_entry_to_file "${folder_path}" "${url}" "${branch}" "${GIT_SUBTREE_SOURCE_FILE}"

    if ! add_file_to_git_index ${GIT_SUBTREE_SOURCE_FILE}; then
        echo "Error, adding file to git index:  "
        return ${ERROR_ADDING_FILE_TO_GIT_INDEX}
    fi

    if ! commit_git_index "${commit_message}"; then
        echo "Error, commiting git index: ${commit_message}"
        return ${ERROR_COMMITING_GIT_INDEX}
    fi

    if [[ ${ACTIVATE_PUSH} == true ]]; then
        if ! push_all_git_commits; then
            echo "Error, pushing git commits to server"
            return ${ERROR_PUSH_GIT_COMMITS}
        fi
    fi

    return ${NO_ERROR}
}

function action_update_all_subtrees() {
    local counter_commits
    if ! exist_file "${GIT_SUBTREE_SOURCE_FILE}"; then
        echo "Error, source file '${GIT_SUBTREE_SOURCE_FILE}' not found!"
        return ${ERROR_SOURCE_FILE_NOT_EXIST}
    fi

    while IFS="," read -r folder_path url branch; do
        count_not_pushed_commits
        counter_commits=${?}

        if ! exist_folder "${folder_path}"; then
            echo "Local folder not exist, add subtree: ${folder_path}"
            if ! add_git_subtree "${folder_path}" "${url}" "${branch}"; then
                echo "Error, git subtree add failed!"
                return ${ERROR_ADDING_GIT_SUBTREE}
            fi
        elif ! update_git_subtree "${folder_path}" "${url}" "${branch}"; then
            echo "Error, updating git subtree: ${folder_path}"
            return ${ERROR_COMMITING_GIT_INDEX}
        fi

        if was_subtree_updated ${counter_commits}; then
            echo "Note update info: ${folder_path}, ${url}, ${branch}"
            note_update_info "${folder_path}" "${url}" "${branch}"
        fi

    done \
        < <(tail -n +2 ${GIT_SUBTREE_SOURCE_FILE})

    if [[ ${ACTIVATE_PUSH} == true ]]; then
        if ! push_all_git_commits; then
            echo "Error, pushing git commits to server"
            return ${ERROR_PUSH_GIT_COMMITS}
        fi
    fi

    return ${NO_ERROR}
}

function action_remove_subtree() {
    local folder_path=${1}
    local commit_message="${COMMIT_MESSAGE_DELETE} ${folder_path}"

    if [[ -z "${folder_path}" ]]; then
        echo "Error, argument missing!"
        echo "Folder: ${folder_path}"
        echo "${SEPERATOR_LINE}"
        usage
        return ${ERROR_ARGUMENTS_MISSING}
    fi

    if ! remove_git_folder_recursive "${folder_path}"; then
        echo "Error removing git folder: ${folder_path}"
        return ${ERROR_REMOVING_GIT_FOLDER}
    fi

    remove_lines_from_file_starting_with_string "${folder_path}" "${GIT_SUBTREE_SOURCE_FILE}"

    if ! add_file_to_git_index "${GIT_SUBTREE_SOURCE_FILE}"; then
        echo "Error, adding file to git index: ${GIT_SUBTREE_SOURCE_FILE}"
        return ${ERROR_ADDING_FILE_TO_GIT_INDEX}
    fi

    if ! commit_git_index "${commit_message}"; then
        echo "Error, commiting git index: ${commit_message}"
        return ${ERROR_COMMITING_GIT_INDEX}
    fi

    if [[ ${ACTIVATE_PUSH} == true ]]; then
        if ! push_all_git_commits; then
            echo "Error, pushing git commits to server"
            return ${ERROR_PUSH_GIT_COMMITS}
        fi
    fi

    return ${NO_ERROR}
}

function list_all_source_file_entries() {
    local entry_nb=1

    if [[ $(exist_file "${GIT_SUBTREE_SOURCE_FILE}") == "${NOT_EXIST}" ]]; then
        echo "Error, source file '${GIT_SUBTREE_SOURCE_FILE}' not found!"
        return ${ERROR_SOURCE_FILE_NOT_EXIST}
    fi

    echo -e "\nList all git subtree entries:"
    echo -e "<Local folder path>, <git url>, <branch>\n"
    while IFS="," read -r folder_path url branch; do
        echo "${entry_nb}.) ${folder_path}, ${url}, ${branch}"
        entry_nb=$((entry_nb + 1))
    done < <(tail -n +2 ${GIT_SUBTREE_SOURCE_FILE})
}

function check_unstaged_changes() {
    local findings=${NO_ERROR}
    if [[ -n "$(git diff --exit-code)" ]]; then
        echo "Unstaged changes found"
        findings=${ERROR_UNSTAGED_CHANGES_FOUND}
    fi

    return ${findings}
}

function check_not_committed_changes() {
    local findings=${NO_ERROR}
    if [[ -n "$(git diff --cached --exit-code)" ]]; then
        echo "Not committed changes found"
        findings=${ERROR_NOT_COMMITTED_CHANGES_FOUND}
    fi

    return ${findings}
}

function check_for_changes() {
    local findings

    check_unstaged_changes
    findings=${?}
    if [[ ${findings} -ne ${NO_ERROR} ]]; then
        return ${findings}
    fi

    check_not_committed_changes
    findings=${?}
    if [[ ${findings} -ne ${NO_ERROR} ]]; then
        return ${findings}
    fi

    return ${findings}
}

function check_everything_pushed() {
    local findings=${NO_ERROR}
    git log "@{u}.." -1 --branches --not --remotes --oneline --exit-code \
        >/dev/null
    local something2Push=${?}

    if [[ ${something2Push} -ne 0 ]]; then
        findings=${ERROR_NOT_EVERYTHING_PUSHED}
    fi

    return ${findings}

}

function count_not_pushed_commits() {
    local counter=0
    counter=$(git log "@{u}.." \
        --branches --not --remotes --oneline --exit-code | wc -l)

    return "${counter}"
}

function add_file_to_git_index() {
    local file=${1}
    git add "${file}"
    return ${?}
}

function commit_git_index() {
    local message=${1}

    git commit -m "${message}"
    return ${?}
}

function push_all_git_commits() {
    git push
    return ${?}
}

function add_git_subtree() {
    local folder_path=${1}
    local url=${2}
    local branch=${3}

    git subtree add --prefix "${folder_path}" "${url}" "${branch}" --squash
    return ${?}
}

function update_git_subtree() {
    local folder_path=${1}
    local url=${2}
    local branch=${3}

    git fetch "${url}" "${branch}"
    git subtree pull --prefix "${folder_path}" "${url}" "${branch}" --squash
    return ${?}
}

function remove_git_folder_recursive() {
    local folder=${1}

    git rm -r -q "${folder}"
    return ${?}
}

function remove_lines_from_file_starting_with_string() {
    local start_string=${1}
    local file=${2}

    ### Prepare search string ###
    local search_char='/'
    local replace_char="\/"
    search_string="/${start_string//${search_char}/${replace_char}},/d"

    sed -i "${search_string}" "${file}"
}

function add_new_entry_to_file() {
    local folder_path=${1}
    local url=${2}
    local branch=${3}
    local file=${4}

    echo -e "${folder_path},${url},${branch}" >>"${file}"
}

function exist_file() {
    local file=${1}

    if [[ -f "${file}" ]]; then
        return ${EXIST}
    fi
    return ${NOT_EXIST}
}

function exist_folder() {
    local path=${1}

    if [ -d "${path}" ]; then
        return ${EXIST}
    fi
    return ${NOT_EXIST}
}

function was_subtree_updated() {
    local last_counter=${1}
    local currend_counter=0

    count_not_pushed_commits
    currend_counter=${?}

    if [[ ${currend_counter} != "${last_counter}" ]]; then
        return ${SUBTREE_WAS_UPDATED}
    fi

    return ${SUBTREE_WAS_NOT_UPDATED}
}

function note_update_info() {
    local folder_path=${1}
    local url=${2}
    local branch=${3}

    if [[ ${ACTIVATE_OUTPUT_FILE} == true ]]; then
        add_new_entry_to_file "${folder_path}" "${url}" "${branch}" "${GIT_SUBTREE_NOTICE_FILE}"
    fi
}

main "$@"
