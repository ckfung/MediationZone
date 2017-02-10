#!/bin/sh

### HOW TO USE ###
# 1. Ensure the directory in this manner
#    |- 3pp/*jar
#    |- jdk-1.*tar.gz
#    |- DR_*.tgz
# 2. Set the manual settings below
# 3. Run the script
# 4. Source file is located at home or predefine location
#

###################################
# START Manual Settings
###################################
MZ_HOME='/opt/mz8rc4/'
MZ_ID=$(basename $MZ_HOME) # use for mz.container
TPP_DIR='/opt/3pp'
JAVA_BASE='/opt/java'

SOURCE_FILE=DEFAULT

# MZ Default Installation Port
# PLATFORM_PORT = 6790
# SYNC_PORT     = 6791
# HTTPD_PORT    = 9090
# WI_PORT       = 9000
PLATFORM_PORT=7420
SYNC_PORT=7421
HTTPD_PORT=7422
WI_PORT=7423

###################################
# END Manual Settings
###################################

###################################
# Functions
###################################
createDirWithSudo() {
  dir=$1
  if [ ! -z $dir ]; then
    if [ -d $dir ]; then
      echo "$dir already exists"
    else
      echo "$dir not exist, creating..."
      sudo mkdir $dir
    fi
  fi
}

createSourceFile() {
  mz_home=$1
  java_home=$2
  source=$3

  if [ $source = DEFAULT ]; then
    source="${HOME}/.source_$MZ_ID.sh"
    SOURCE_FILE=$source
  fi

  echo '# auto-generated source file' > $source
  echo "" >> $source

  echo "MZ_HOME='$mz_home'" >> $source
  echo "JAVA_HOME='$java_home'" >> $source
  echo "" >> $source

  echo "export MZ_HOME" >> $source
  echo "export JAVA_HOME" >> $source
  echo "" >> $source

  echo 'PATH=$MZ_HOME/bin:$JAVA_HOME/bin:$PATH' >> $source
}

######################################
# Start execution
######################################
CURR_DIR=$(pwd)
export MZ_HOME

if [ -d $MZ_HOME ]; then
  echo "$MZ_HOME already exists, aborting..."
  exit 1
fi

echo '##################################'
echo "# Environment Preparation"
echo '##################################'
createDirWithSudo $MZ_HOME
createDirWithSudo $JAVA_BASE
createDirWithSudo $TPP_DIR

echo "Change MZ_HOME owner to mzadmin"
sudo chown mzadmin:mzadmin $MZ_HOME
sudo chmod 775 $MZ_HOME

echo

echo '##################################'
echo "# 3PP ($TPP_DIR)"
echo '##################################'
for i in $(ls $CURR_DIR/3pp/*jar)
do
  jar_file=$(basename $i)
  if [ ! -f $TPP_DIR/$jar_file ]; then
    echo "Installing $jar_file to $TPP_DIR ..."
    sudo cp $CURR_DIR/3pp/$jar_file $TPP_DIR
  else
    echo "$i already exists, not copied"
  fi
done

echo

echo '##################################'
echo "# JAVA ($JAVA_BASE)"
echo '##################################'

# check if any jdk package included in the installation
if [ ! -z $(ls $CURR_DIR/jdk-*tar.gz) ]; then
  java_package=$(tar -tlf jdk-*tar.gz | head -1 | sed 's=/==g')
  JAVA_HOME=$JAVA_BASE/$java_package

  echo "Found package $java_package for installation"

  # check if same package already installed
  if [ -d $JAVA_HOME ]; then
    echo "Same java package already exists, not installing !!"
  else
    echo "unzipping $(ls jdk-*tar.gz)"
    tar -zxf jdk-*.tar.gz 
    sudo mv $java_package $JAVA_BASE
  fi
else
  # auto determine jdk from JAVA_BASE
  echo "Finding java from existing JAVA_BASE..."
  JAVA_HOME=$(ls -d $JAVA_BASE/* | sort | tail -1)
fi

# set JAVA_HOME for installation
if [ ! -z $JAVA_HOME ]; then
  # Reset the java path
  export JAVA_HOME
  export PATH=$JAVA_HOME/bin:${PATH}

  # display new java version
  java -version
else 
  exit 2
fi

echo

echo '##################################'
echo "# MZ HOME ($MZ_HOME)"
echo '##################################'
mz_package=$(ls ./D*tgz)
if [ -f $mz_package ]; then
  echo "unzipping $mz_package"
  tar -zxf $mz_package
  cd D*
  ./setup.sh prepare 

  echo
  echo Changing install.xml

  sed_mz_home=$(echo $MZ_HOME | sed 's=\/=\\\/=g')
  sed_3pp_dir=$(echo $TPP_DIR | sed 's=\/=\\\/=g')

  sed -i "s/install.security\" value=\"true\"/install.security\" value=\"false\"/" install.xml
  sed -i "s/mz.container\" value=\"\"/mz.container\" value=\"$MZ_ID\"/" install.xml
  sed -i "s/\/opt\/mz/$sed_mz_home/" install.xml
  sed -i "s/\/opt\/3pp/$sed_3pp_dir/" install.xml

  if [ ! -z $PLATFORM_PORT ]; then
    sed -i "s/6790/$PLATFORM_PORT/g" install.xml
  fi

  if [ ! -z $SYNC_PORT ]; then
    sed -i "s/6791/$SYNC_PORT/g" install.xml
  fi

  if [ ! -z $HTTPD_PORT ]; then
    sed -i "s/9090/$HTTPD_PORT/g" install.xml
  fi

  if [ ! -z $WI_PORT ]; then
    sed -i "s/9000/$WI_PORT/g" install.xml
  fi
  ./setup.sh create
  ./setup.sh install
fi

echo "Creating source file"
createSourceFile $MZ_HOME $JAVA_HOME $SOURCE_FILE

echo "Installation Finish"
exit 0

