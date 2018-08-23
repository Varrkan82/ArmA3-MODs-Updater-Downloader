#!/bin/bash

: << LICENSE

MIT License

Copyright (c) 2018 Vitalii Bieliavtsev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

LICENSE

: << EXITCODES

1 - Some external program error
2 - No authentication data for Steam account
3 - Wrong selection
4 - Wrong MODs name
5 - Can not creeate the symbolic link
6 - Wrong MODs ID in "meta.cpp" file ("0" as usually)
7 - Interrupted by user

EXITCODES

# Mandatory variables
STMAPPID="107410"                 # AppID of an ArmA 3 which used to download the MODs. Should not be changed usually.
CURRYEAR=$(date +%Y)                  # Current year
CURL_CMD="/usr/bin/curl -s"               # CURL command
STEAM_CHLOG_URL="https://steamcommunity.com/sharedfiles/filedetails/changelog"    # URL to get the date of the last MOD's update in a WorkShop
# Change it according to your paths
STMCMD_PATH="/home/steam/arma3server/steamcmd"            # Path to 'steamcmd.sh' file
INST_MODS_PATH="/home/steam/arma3server/serverfiles/mods"       # Path to ArmA 3 installed MODs in an installed  ArmA 3 server's directory
WKSHP_PATH="/home/steam/Steam/steamapps/workshop"         # Path to there is Workshop downloaded the MODs

# Optional variables
STEAM_LOGIN=""                    # Steam login (with a purchased ArmA 3)
STEAM_PASS=""                   # Steam password

# Check for needed paths and for CURL
if [[ ! -d "${STMCMD_PATH}" || ! -d "${INST_MODS_PATH}" || ! -d "${WKSHP_PATH}" ]]; then
  echo "Some path(s) is/(are) missing. Check - does an all paths are correctly setted up! Exit."
  exit 11
elif [[ ! -f "${CURL_CMD}" ]]; then
  echo "CURL is missing. Check - does it installed and pass the correct path to it into variable 'CURL_CMD'. Exit."
fi

## Functions
authcheck(){
  # Checking for does the Steam login and password are pre-configured?
  if [[ -z "${STEAM_LOGIN}" ]]; then
    clear
    read -e -p "Steam login is undefined. Please, enter it now: " STEAM_LOGIN
    if [[ -z "${STEAM_LOGIN}" ]]; then
      echo -ne "Steam login not specified! Exiting!\n"
      exit 2
    fi
  fi
  if [[ -z "${STEAM_PASS}" ]]; then
    clear
    read -sep "Steam password is undefined. Please, enter it now (password will not be displayed in console output!): " STEAM_PASS
    if [[ -z "${STEAM_PASS}" ]]; then
      echo -ne "Steam password not specified! Exiting!\n"
      exit 2
    fi
  fi
  clear
}

backupwkshpdir(){
set -x
  if [[ -d "${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}" ]]; then
echo "$?"
    echo "Workshop target directory for MOD ${MOD_NAME} is already present. Moving it to ${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}_old_$(date +%y%m%d-%H%M)"
    mv -f "${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}" "${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}_old_$(date +%y%m%d-%H%M)"
echo $?
  fi
set +x
}

backupmoddir(){
set -x
  if [[ -L "${INST_MODS_PATH}/${MOD_NAME}" ]]; then
echo "$?"
    rm ${INST_MODS_PATH}/${MOD_NAME}
echo "$?"
  elif [[ -d "${INST_MODS_PATH}/${MOD_NAME}" ]]; then
echo "$?"
    mv "${INST_MODS_PATH}/${MOD_NAME}" "${INST_MODS_PATH}/${MOD_NAME}_old_$(date +%y%m%d-%H%M)"
echo "$?"
  fi
set +x
}

get_mod_name(){
  grep -h "name" "${MODS_PATH}"/meta.cpp | \
  awk -F'"' '{print $2}' | \
  tr -d "[:punct:]" | \
  tr "[:upper:]" "[:lower:]" | \
  sed -E 's/\s{1,}/_/g' | \
  sed 's/^/\@/g'
}

get_mod_id(){
  grep -h "publishedid" "${MODS_PATH}"/meta.cpp | \
  awk '{print $3}' | \
  tr -d [:punct:]
}

get_wkshp_date(){
  if [[ "$(${CURL_CMD} ${URL} | grep -m1 "Update:" | wc -w)" = "7" ]]; then
    PRINT="$(${CURL_CMD} ${URL} | grep -m1 "Update:" | tr -d "," | awk '{ print $2" "$3" "$4" "$6 }')"
  else
    PRINT="$(${CURL_CMD} ${URL} | grep -m1 "Update:" | awk '{ print $2" "$3" "'${CURRYEAR}'" "$5 }')"
  fi
  WKSHP_UP_ST="${PRINT}"
}

countdown(){
  local TIMEOUT="10"
  for (( TIMER="${TIMEOUT}"; TIMER>0; TIMER--)); do
    printf "\rDisplay the list in: ${TIMER} or\n Press any key to continue without waiting... :)"
    read -s -t 1 -n1
    if [[ "$?" = "0" ]]; then
      break
    fi
    echo "Press any key to continue without waiting... :)"
    clear
  done
}

checkupdates(){
  echo "Checking for updates..."
  # check all installed MODs for updates.
  TO_UP=( )
  MOD_UP_CMD=( )
  MOD_ID_LIST=( )
  for MOD_NAME in "${INST_MODS_LIST[@]}"; do
    MODS_PATH="${INST_MODS_PATH}/${MOD_NAME}"
    MOD_ID=$(get_mod_id)
    MOD_ID="${MOD_ID%$'\r'}"
    URL="${STEAM_CHLOG_URL}/${MOD_ID}"
    URL="${URL%$'\r'}"

    get_wkshp_date

    UTIME=$(date --date="${WKSHP_UP_ST}" +%s)
    CTIME=$(date --date="$(stat ${MODS_PATH} | grep Modify | cut -d" " -f2-)" +%s ) 				#Fix for MC syntax hilighting #"

    if [[ "${MOD_ID}" = "0" ]]; then
      echo -ne "\033[37;1;41mWrong ID for MOD ${MOD_NAME} in file 'meta.cpp'\033[0m You can update it manually and the next time it will be checked well. \n"
      continue
    else
      # Compare update time
      if [[ ${UTIME} -gt ${CTIME} ]]; then
        # Construct the list of MODs to update
        MOD_UP_CMD+=+"workshop_download_item ${STMAPPID} ${MOD_ID} "
        TO_UP+="${MOD_NAME} "
        MOD_ID_LIST+="${MOD_ID} "
        echo -en "\033[37;1;42mMod ${MOD_NAME} can be updated.\033[0m\n"

        continue
      else
        echo "MOD ${MOD_NAME} is already up to date!"
        continue
      fi
    fi
  done
  export MOD_ID
  export MOD_UP_CMD
  export MOD_ID_LIST
  export TO_UP
}

update_all(){
set -x
  for MOD_NAME in "${TO_UP[@]}"; do
echo "$MOD_NAME"
    backupmoddir
  done
echo "${MOD_UP_CMD[@]}"
#  ${STMCMD_PATH}/steamcmd.sh +login ${STEAM_LOGIN} ${STEAM_PASS} "${MOD_UP_CMD[@]}" validate +quit
  for MOD_ID in "${MOD_ID_LIST[@]}"; do
    backupwkshpdir
echo ${WKSHP_PATH}/content/${STMAPPID}/"${MOD_ID}"
#    find ${WKSHP_PATH}/content/${STMAPPID}/"${MOD_ID}" -depth -exec rename 's/(.*)\/([^\/]*)/$1\/\L$2/' {} \;
  done
set -x
}

: << INPROGRESS
batchfixes(){
  for MOD_NAME in "${INST_MODS_LIST[@]}"; do
    MODS_PATH="${INST_MODS_PATH}/${MOD_NAME}"
    MOD_ID=$(get_mod_id)
    MOD_ID="${MOD_ID%$'\r'}"
    OLD_WKSHP_PATH=($(find ${WKSHP_PATH}/content/${STMAPPID} -type d -name "*_old_*"))
    OLD_TARGET_PATH=($(find ${INST_MODS_PATH} -type d -name "*_old_*"))
    fixappid
  find "${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}" -depth -exec rename 's/(.*)\/([^\/]*)/$1\/\L$2/' {} \;
}
INPROGRESS

update_mod(){
  rm -rf "${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}"
  "${STMCMD_PATH}"/steamcmd.sh +login "${STEAM_LOGIN}" "${STEAM_PASS}" "${MOD_UP_CMD}" validate +quit
  if [[ "$?" != "0" ]]; then
    echo -ne "Unknown error while downloading from Steam Workshop. Exiting.\n"
    exit 1
  else
    echo -e "\n"
    return 0
  fi
}

download_mod(){
  "${STMCMD_PATH}"/steamcmd.sh +login "${STEAM_LOGIN}" "${STEAM_PASS}" "${MOD_UP_CMD}" validate +quit
  if [[ "$?" != "0" ]]; then
    echo "Unknown error while downloading from Steam Workshop. Exiting."
    exit 1
  else
    echo -e "\n"
    return 0
  fi
}

simplequery(){
  SELECT=false
  while ! $SELECT; do
    read -e -p "Enter [y|Y]-Yes, [n|N]-No or [quit]-to abort: " ANSWER
    case "${ANSWER}" in
      y | Y )
        SELECT=true
        true
        ;;
      n | N )
        SELECT=true
        false
        ;;
      quit )
        echo "\033[37;1;41mWarning!\033[0m Some important changes wasn't made. This could or not to cause the different problems."
        exit 7
	      ;;
      * )
        echo -ne "Wrong selection! Try again or type 'quit' to interrupt process.\n"
        ;;
    esac
  done
}

fixappid(){
  if [[ "$?" = "0" ]]; then
    if [[ -z "$1" ]]; then
      GET_ID_PATH="${MODS_PATH}"
    else
      GET_ID_PATH="${1}"
    fi
    DMOD_ID=$(get_mod_id)         # Downloaded MODs ID
    DMOD_ID="${DMOD_ID%$'\r'}"
    if [[ "${DMOD_ID}" = "0" ]]; then
      echo "Steam ApplicationID is 0. Will try to fix."
      sed -i 's/^publishedid.*$/publishedid \= '${MOD_ID}'\;/' "${MODS_PATH}"/meta.cpp
      if [[ "$?" = "0" ]]; then
        echo "Steam ApplicationID is fixed."
      fi
    fi
  fi
}
## End of a functions block

# List installed mods
INST_MODS_LIST=($(ls -1 "${INST_MODS_PATH}"| grep -v "_old_" ))

clear

# Ask user for action
echo -ne "After selecting to 'Update' -> 'Single' - you will see the list of installed MODs.\n\033[37;1;41mPlease, copy the needed name before exiting from the list.\nIt will be unavailabe after exit.\nTo get the list again - you'll need to restart the script\033[0m\n"
echo -ne "What do you want to do? \n [u|U] - Update MOD \n [c|C] - Check all MODs for updates\n [d|D] - Download MOD?"
echo -ne "Any other selection will cause script to stop.\n"

read -e -p "Make selection please: " ACTION

case "${ACTION}" in
  # Actions section
  c | C )
    checkupdates

    # Print MODs which could be updated
    if [[ ! -z "${TO_UP[@]}" ]]; then
      echo -ne "Mods ${TO_UP[*]} can be updated. Please, proceed manually."
    else
      echo "All MODs are up to date. Exiting."
      exit 0
    fi
    ;;
  u | U )
    clear
    # Ask user to select update mode
#    echo -ne "How do you want to update? [b|B]-Batch or [s|S]-Single MOD?\n"

    read -e -p "How do you want to update? [b|B]-Batch or [s|S]-Single MOD? " UPD_M
    case "${UPD_M}" in
      b | B )
	# Check updates for installed MODs
        checkupdates
        # Print MODs which could be updated
        if [[ ! -z "${TO_UP[@]}" ]]; then
          simplequery
          echo -e "Mods ${TO_UP[@]} can be updated. Do you want to proceed? [y|Y] or [n|N]: "

          if [[ "$?" = "0" ]]; then
            authcheck
            update_all
          else
            exit 7
          fi

        else
          echo "All MODs are up to date. Exiting."
          exit 0
        fi
        ;;
      s | S )
        authcheck

        countdown

        echo -ne "$(ls ${INST_MODS_PATH})\n" | less
        echo -ne "Please, specify MOD's name (with '@' symbol in the begining too).\n"
        # Ask user to enter a MOD's name to update
        echo -ne "You have installed a MODs listed above. Please, enter the MODs name to update:\n"
        read -er MOD_NAME

	      echo "Starting to update MOD ${MOD_NAME}..."
        # Check syntax
        if [[ "${MOD_NAME}" != @* && "${MOD_NAME}" != "" ]]; then
          echo -ne "Wrong MOD's name! Exiting!\n"
          exit 4
        else
          # Update the single selected MOD
          MODS_PATH="${INST_MODS_PATH}/${MOD_NAME}"
          MOD_ID=$(get_mod_id)
          MOD_ID="${MOD_ID%$'\r'}"

          if [[ "${MOD_ID}" = "0" ]]; then
            echo -ne "MOD application ID is not configured for mod ${MOD_NAME} in file ${MODS_PATH}/meta.cpp \n"
            echo -ne "Find it by the MODs name in a Steam Workshop and update in MODs 'meta.cpp' file or use Download option to get MOD by it's ID. Exiting.\n"
            exit 6
          fi

          URL="${STEAM_CHLOG_URL}/${MOD_ID}"
          URL="${URL%$'\r'}"

          get_wkshp_date

          UTIME=$(date --date="${WKSHP_UP_ST}" +%s)
          CTIME=$(date --date="$(stat ${MODS_PATH} | grep Modify | cut -d" " -f2-)" +%s )   #Fix for MC syntax hilighting #"
          if [[ ${UTIME} -gt ${CTIME} ]]; then
            MOD_UP_CMD=+"workshop_download_item ${STMAPPID} ${MOD_ID}"
            echo "${MOD_UP_CMD}"

            backupwkshpdir
            update_mod

            if [[ "$?" = "0" ]]; then
              echo "MODs updateis successfully downloaded to ${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}"

              backupmoddir

              ln -s "${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}" "${MODS_PATH}"

              if [[ "$?" = "0" ]]; then
                echo "\033[37;1;42mMOD is updated. Symbolik link to ${MODS_PATH} is created.\033[0m"
                fixappid "${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}"
              else
                echo -ne "\033[37;1;41mWarning!\033[0m Can't create symbolic link to a target MODs directory. Exit.\n"
                exit 5
              fi

              # Ask user to transform the names from upper to lower case
              echo "Do you want to transform all files and directories names from UPPER to LOWER case?"

              simplequery

              if [[ "$?" = "0" ]]; then
                find "${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}" -depth -exec rename 's/(.*)\/([^\/]*)/$1\/\L$2/' {} \;
                exit 0
              elif [[ "$?" = "1" ]]; then
                echo -ne "\033[37;1;41mWarning!\033[0m You're selected to DO NOT transform the Upper case letters in a MOD's directory and file name.\n It could cause the probles connecting the MOD to ArmA 3.\n"
              fi

            fi
          else
            echo -ne "\033[37;1;42mMOD ${MOD_NAME} is already up to date.\033[37;1;42m\n"
            exit 0
          fi
        fi
        ;;
      * )
        echo -ne "Wrong selection! Exiting.\n"
        exit 7
        ;;
    esac
    ;;

  d | D )
    # Download section
    authcheck
    echo ""
    # Ask user to enter a MOD Steam AppID
    read -e -p "Please, enter an Application ID in a Steam WokrShop to dowdnload: " MOD_ID
    echo "Application ID IS: ${MOD_ID}\n"
    echo "Starting to download MOD ID ${MOD_ID}..."
    MODS_PATH="${WKSHP_PATH}/content/${STMAPPID}/${MOD_ID}"
    MOD_UP_CMD=+"workshop_download_item ${STMAPPID} ${MOD_ID}"
    echo "${MOD_UP_CMD}"

    download_mod

    fixappid

    # Ask user to create the symbolic link for downloaded MOD to an ArmA 3 Server's mods folder
    echo  "Do you want to symlink the downloaded MOD to your MODs folder in ARMA3Server folder? [y|Y] or [n|N]: "

    simplequery

    if [[ "$?" = "0" ]]; then
      MOD_NAME=$(get_mod_name)

      backupmoddir

      ln -s "${MODS_PATH}" "${INST_MODS_PATH}"/"${MOD_NAME}"

      if [[ "$?" = "0" ]]; then
        echo -ne "\033[37;1;42mMOD is downloaded. Symbolik link from ${MODS_PATH} to ${INST_MODS_PATH}/${MOD_NAME} is created.\033[0m\n"
      else
        echo -ne "\033[37;1;41mWarning!\033[0m Can't create symbolic link to a target MODs directory. Exit.\n"
        exit 5
      fi
    elif [[ "$?" = "1" ]]; then
      echo -ne "Done! Symbolic link not created!\n"
    fi

    # Ask user to transform the names from upper to lower case
    echo -ne "Do you want to transform all file's and directories names from UPPER to LOWER case?\n"

    simplequery

    if [[ "$?" = "0" ]]; then
      find "${MODS_PATH}" -depth -exec rename 's/(.*)\/([^\/]*)/$1\/\L$2/' {} \;
      exit 0
    elif [[ "$?" = "1" ]]; then
      echo -ne "\033[37;1;41mWarning!\033[0m You're selected to DO NOT transform the Upper case letters in a MOD's directory and file name.\n It could cause the probles with connecting the MOD to ArmA 3.\n"
      echo ""
      exit 0
    fi
    ;;

  * )
    echo -ne "Wrong selection! Exiting!\n"
    exit 3
    ;;
esac
echo ""

exit 0
