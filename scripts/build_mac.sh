#!/bin/bash

echo "========= OnTheSpot macOS Build Script =========="

# Parse command line arguments
# --keep-build-dirs: Preserve build, builder, and venv directories for faster incremental builds
#                    Useful for local development to avoid re-downloading/re-building ffmpeg
#                    and re-installing Python dependencies on each build
#                    Default behavior (without flag) is to clean these directories
KEEP_BUILD_DIRS=false
if [[ "$*" == *--keep-build-dirs* ]]; then
    KEEP_BUILD_DIRS=true
    echo " => Running in incremental build mode (build/builder/venv directories will be preserved)"
fi


echo " => Cleaning up previous builds and preparing the environment..."
rm -f ./dist/OnTheSpot.tar.gz
mkdir -p build
mkdir -p dist
mkdir -p builder

# Create and populate virtual environment only in clean build mode
# In incremental mode, reuse existing venv to skip dependency reinstallation
# If venv doesn't exist even in incremental mode, create it
if [ "$KEEP_BUILD_DIRS" = false ] || [ ! -d "venv" ]; then
    if [ "$KEEP_BUILD_DIRS" = true ] && [ ! -d "venv" ]; then
        echo " => Virtual environment not found, creating it..."
    else
        echo " => Creating virtual environment..."
    fi
    # Find the best Python 3 executable (prefer stable 3.12, 3.11, or 3.10 over newer drafts like 3.14 for PyInstaller/PyQt6 stability on macOS 12)
    PYTHON_EXE="python3"
    for py in "python3.12" "python3.11" "python3.10" "python3"; do
        if command -v "$py" &>/dev/null; then
            PYTHON_EXE="$py"
            break
        fi
    done
    echo " => Using Python executable: $PYTHON_EXE"

    $PYTHON_EXE -m venv venv
    source ./venv/bin/activate

    echo " => Upgrading pip and installing necessary dependencies..."
    venv/bin/pip install --upgrade pip wheel pyinstaller
    # Explicitly pin PyQt6-Qt6 to the same version as PyQt6 (6.6.1) to avoid downloading
    # the latest PyQt6-Qt6 binaries (which require macOS 13+ and fail on macOS 12)
    venv/bin/pip install "pyqt6==6.6.1" "PyQt6-Qt6==6.6.1" "pyqt6-sip>=13.6.0"
    venv/bin/pip install -r requirements.txt
else
    echo " => Reusing existing virtual environment..."
    source ./venv/bin/activate
fi


echo " => Build FFMPEG (Optional)"

if uname -m | grep -q x86_64; then
	if ! [ -f "dist/ffmpeg" ]; then
    	curl -L -o build/ffmpeg.zip https://evermeet.cx/ffmpeg/ffmpeg-7.1.zip
    	unzip build/ffmpeg.zip -d dist
	#    cd build
	#    curl https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz -o ffmpeg.tar.xz
	#    tar xf ffmpeg.tar.xz
	#    cd ffmpeg-*
	#    ./configure --enable-small --disable-ffplay --disable-ffprobe --disable-doc --disable-htmlpages --disable-manpages --disable-podpages --disable-txtpages
	#    make
	#    cp ffmpeg ../../dist
	#    cd ../..
	fi
else
    if ! [ -f "dist/ffmpeg" ]; then
        curl -L -o build/ffmpeg.zip https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip
        unzip build/ffmpeg.zip -d dist
    fi
fi


FFBIN="--add-binary=dist/ffmpeg:onthespot/bin/ffmpeg"



echo " => Running PyInstaller to create .app package..."
venv/bin/pyinstaller --windowed \
    --hidden-import="zeroconf._utils.ipaddress" \
    --hidden-import="zeroconf._handlers.answers" \
    --add-data="src/onthespot/qt/qtui/*.ui:onthespot/qt/qtui" \
    --add-data="src/onthespot/resources/icons/*.png:onthespot/resources/icons" \
    --add-data="src/onthespot/resources/translations/*.qm:onthespot/resources/translations" \
    $FFBIN \
    --paths="src/onthespot" \
    --name="OnTheSpot" \
    --icon="src/onthespot/resources/icons/onthespot.png" \
    src/portable.py


echo " => Setting executable permissions..."
chmod +x dist/OnTheSpot.app


echo " => Creating dmg..."
rm -rf dist/dmg
rm -f dist/OnTheSpot.dmg
mkdir -p dist/dmg
mv dist/OnTheSpot.app dist/dmg/OnTheSpot.app
ln -s /Applications dist/dmg

echo "# Login Issues
Newer versions of macOS have restricted networking features
for apps inside the 'Applications' folder. To login to your
account you will need to:

1. Run the following command in terminal, 'echo \"127.0.0.1 \$HOST\" | sudo tee -a /etc/hosts'

2. Launch the app and click add account before dragging into the applications folder.

3. After successfully logging in you can drag the app into the folder.


# Security Issues
After all this, if you experience an error while trying to launch
the app you will need to open the 'Applications' folder, right-click
the app, and click open anyway." > dist/dmg/readme.txt

hdiutil create -srcfolder dist/dmg -format UDZO -o dist/OnTheSpot.dmg


echo " => Cleaning up temporary files..."
rm -rf __pycache__ *.spec

# Clean build directories and venv unless --keep-build-dirs flag is set
# This removes downloaded ffmpeg sources, build artifacts, and Python dependencies
# Skip cleanup in development mode to speed up subsequent builds
if [ "$KEEP_BUILD_DIRS" = false ]; then
    echo " => Removing build, builder, and venv directories..."
    rm -rf build builder venv
else
    echo " => Preserving build, builder, and venv directories for incremental builds"
fi


echo " => Done! .dmg available in 'dist/OnTheSpot.dmg'."
