#!/bin/sh
# Copyright 2017 Digital Route AB. All rights reserved.
# DIGITAL ROUTE AB PROPRIETARY/CONFIDENTIAL.
# Use is subject to license terms.
#
# Core 7.2.x

# color scheme
NORMAL=`echo "\033[m"`
MENU=`echo "\033[36m"` #Blue
YELLOW=`echo "\033[33m"` #yellow
RED_TEXT=`echo "\033[31m"` #red
FGRED=`echo "\033[41m"` #highlighted

SAVEIFS=$IFS
IFS=","

CURRENT_DIR=$(pwd)
SYSEXPORT_DIR="$CURRENT_DIR/__mztmp_sysexport"
WORKING_FOLDER="__mztmpFolder"
WFL_FILE_PREFIX="__mztmp_workflow."
WFL_LIST_FILE="${WFL_FILE_PREFIX}workflowlist"
DEP_FOLDER="dep_to_remove"
OUTPUT_FILE_PREFIX="REFERENCE_LIST."

quit() {
    IFS=$SAVEIFS
    cd $CURRENT_DIR
    exit $1
}

spinner() {
    local pid=$!
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf ". [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

mzSysExport() {
    local user="mzadmin"
    local password=${1}

    mzsh $user/$password systemexport -overwrite -directory $SYSEXPORT_DIR > /dev/null & spinner
}

extractWorkflow() {
    for wflFolder in $(grep "Workflow_order" ../metadata.properties | cut -f1 -d"="); do
        for workflow in $(grep $wflFolder ../metadata.properties | cut -f2 -d"="); do
            local wfl=$(echo $workflow | cut -f4 -d"/")
            if [[ $wfl != "" ]] && [[ $wfl != "SystemTask"* ]]; then
                echo $wfl >> $WFL_LIST_FILE
            fi
        done
    done
}

extractDependencies() {
    mkdir -p $DEP_FOLDER
    while read -r wflname _; do
        local cnt=1
        local next=1
        local last=1

        local wflDepFile=$DEP_FOLDER"/"${WFL_FILE_PREFIX}${wflname}"."${cnt}
        for dep in $(grep $wflname"_dependencies" ../metadata.properties | cut -f2 -d"="); do
            if [[ $dep != "" ]]; then
                echo $dep | cut -f4 -d"/" >> $wflDepFile
            fi
        done

        while true; do
            wflDepFile=$DEP_FOLDER"/"${WFL_FILE_PREFIX}${wflname}"."${cnt}
            
            if [ -f $wflDepFile ] && [ -s $wflDepFile ]; then
                next=$((last+1))
                wflMoreDepFile=$DEP_FOLDER"/"${WFL_FILE_PREFIX}${wflname}"."${next}
                cat $wflDepFile | sort | uniq > $wflDepFile".bak"; mv $wflDepFile".bak" $wflDepFile
                while read -r data _; do
                    for moredep in $(grep $data"_dependencies" ../metadata.properties | cut -f2 -d"="); do
                        if [[ $moredep != "" ]]; then
                            echo $moredep | cut -f4 -d"/" >> $wflMoreDepFile
                        fi
                    done
                done < $wflDepFile
                last=$next
                cnt=$((cnt+1))
            else
                break;
            fi
        done

        # concatenate if more than one file is found
        if [ -s $DEP_FOLDER"/"${WFL_FILE_PREFIX}${wflname}".1" ]; then
            cat $DEP_FOLDER"/"${WFL_FILE_PREFIX}${wflname}"."* | sort | uniq > ${WFL_FILE_PREFIX}${wflname}
        fi
    done < $WFL_LIST_FILE
    rm -rf $DEP_FOLDER
}

showResult() {
    output=${OUTPUT_FILE_PREFIX}${searchConfig}".tmp"
    grep $searchConfig $WFL_FILE_PREFIX* | sed 's/^__mztmp_workflow.//' > $output

    echo -e "\n\n${YELLOW}Please find the reference workflow for ${RED_TEXT}$searchConfig${NORMAL} listed below."
    echo -e "${RED_TEXT}--------------------------------------------------------------------------------------------------${NORMAL}"
    printf '%-50s %s\n' "Config" "Workflow"
    echo -e "${RED_TEXT}--------------------------------------------------------------------------------------------------${NORMAL}"

    num=0
    if [ -s $output ]; then
        while read -r useRef _; do
            local result=$(echo $useRef | cut -f1 -d":")
            local matchKey=$(echo $useRef | cut -f2 -d":")

            if [[ $matchKey == $searchConfig ]]; then
                printf '%-50s %s\n' $matchKey $result
                echo $useRef >> ${OUTPUT_FILE_PREFIX}${searchConfig}".txt"
                num=$((num+1))
            fi
        done < $output
    fi

    echo -e "${RED_TEXT}--------------------------------------------------------------------------------------------------${NORMAL}"
    echo -e "${YELLOW}TOTAL FOUND: $num ${NORMAL}\n"

    rm ${OUTPUT_FILE_PREFIX}${searchConfig}"."*
}

if [ -z $MZ_HOME ]; then
    echo "WARNING: MZ_HOME MUST BE SET TO RUN THIS SCRIPT"
    quit 1
fi

if [ ! -d $MZ_HOME ]; then
    echo "WARNING: MZ_HOME DIRECTORY DOES NOT EXIST! ( $MZ_HOME )"
    quit 1
fi

clear; echo ""

while true; do
    read -p "Please enter config name with full path (e.g. Common.UFL_Audit): " searchConfig
    case $searchConfig in
      [a-zA-Zi0-9]* )
          break;;
    esac
done

while true; do
    read -p "Perform MZ systemexport (y/n): " exportFlag
    case $exportFlag in
      y|n ) break;;
    esac
done

depFlag="y"

if [[ $exportFlag == "y" ]]; then
    read -s -p "Please enter mzadmin password: " mzpswd
    echo -e "\n\n${YELLOW}Extracting MZ config ... ${NORMAL}"
    mzSysExport $mzpswd
else
    while true; do
        read -p "Build MZ dependencies list (y/n): " depFlag
        case $depFlag in
          y|n ) break;;
        esac
    done
fi

if [ ! -f "$SYSEXPORT_DIR/metadata.properties" ]; then
    echo ""
    echo "WARNING: MZ META DATA FILE NOT FOUND. PLEASE PERFORM MZ SYSEXPORT!"
    quit 1
fi

cd $SYSEXPORT_DIR
mkdir -p $WORKING_FOLDER ; cd $WORKING_FOLDER

if [[ $depFlag == "y" ]]; then
    rm -rf "$WFL_FILE_PREFIX"*
    extractWorkflow

    if [ -f $WFL_LIST_FILE ] && [ -s $WFL_LIST_FILE ]; then
        echo -e "\n${YELLOW}Extracting MZ dependencies ... ${NORMAL}"
        extractDependencies > /dev/null & spinner
    else
        echo ""
        echo "WARNING: NO WORKFLOW FOUND!"
        quit 1
    fi
fi

showResult
#cd ../ ; rm -rf $WORKING_FOLDER
cd $CURRENT_DIR
quit 0
