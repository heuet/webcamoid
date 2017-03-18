#!/bin/sh

APPNAME=webcamoid

detectqmake() {
    if qmake-qt5 -v 1>/dev/null 2>/dev/null; then
        echo qmake-qt5
    elif qmake -qt=5 -v 1>/dev/null 2>/dev/null; then
        echo qmake -qt=5
    elif qmake -v 1>/dev/null 2>/dev/null; then
        echo qmake
    fi
}

QMAKE=$(detectqmake)

rootdir() {
    dir=$(dirname $PWD/$1)/../../..

    pushd $dir 1>/dev/null
        echo $PWD
    popd 1>/dev/null
}

ROOTDIR=$(rootdir $0)

prepare() {
    if [ -e "${ROOTDIR}/build/bundle-data/${APPNAME}" ]; then
        return
    fi

    sysqmlpath=$(${QMAKE} -query QT_INSTALL_QML)
    insqmldir=${ROOTDIR}/build/bundle-data/$sysqmlpath
    dstqmldir=${ROOTDIR}/build/bundle-data/${APPNAME}/lib/qt/qml

    pushd ${ROOTDIR}
        make INSTALL_ROOT="${ROOTDIR}/build/bundle-data" install
        mv -f "${ROOTDIR}/build/bundle-data/usr" "${ROOTDIR}/build/bundle-data/${APPNAME}"

        if [ "$insqmldir" != "$dstqmldir" ]; then
            mkdir -p "$dstqmldir"
            cp -rf "$insqmldir"/* "$dstqmldir/"
        fi
    popd
}

listqtmodules() {
    bundleData=${ROOTDIR}/build/bundle-data
    scanpaths=(${APPNAME}/bin
               ${APPNAME}/lib)

    for scanpath in ${scanpaths[@]}; do
        find ${bundleData}/${scanpath} -name 'lib*.so*' -or -name ${APPNAME} | \
        while read scanlib; do
            ldd $scanlib | \
            while read lib; do
                lib=$(echo $lib | awk '{print $1}')
                lib=$(basename $lib)
                lib=$(echo $lib | awk -F. '{print $1}')
                lib=${lib:3}

                if [[ "$lib" == Qt5* ]]; then
                    echo $lib
                fi
            done
        done
    done
}

scanimports() {
    find $1 -iname '*.qml' -type f -exec grep "^import \w\{1,\}" {} \;
    find $1 -iname 'qmldir' -type f -exec grep '^depends ' {} \;
}

qmldeps() {
    libpath=${ROOTDIR}/build/bundle-data/${APPNAME}/lib
    sysqmlpath=$(${QMAKE} -query QT_INSTALL_QML)
    qmlsearchdir=(StandAlone/share/qml
                  libAvKys/Plugins
                  build/bundle-data/${APPNAME}/lib/qt/qml)

    for searchpath in "${qmlsearchdir[@]}"; do
        scanimports "${ROOTDIR}/$searchpath" | sort | uniq | \
        while read qmlmodule; do
            modulename=$(echo $qmlmodule | awk '{print $2}')
            moduleversion=$(echo $qmlmodule | awk '{print $3}')
            modulepath=$(echo $modulename | tr . / )
            majorversion=$(echo $moduleversion | awk -F. '{print $1}')

            if (( $majorversion > 1 )); then
                modulepath=$modulepath.$majorversion
            fi

            if [[ -e $sysqmlpath/$modulepath
                  && ! -e $libpath/qt/qml/$modulepath ]]; then
                mkdir -p $libpath/qt/qml/$modulepath
                cp -rf "$sysqmlpath/$modulepath"/* "$libpath/qt/qml/$modulepath"
            fi
        done
    done
}

pluginsdeps() {
    bundleData=${ROOTDIR}/build/bundle-data
    libpath=${bundleData}/${APPNAME}/lib

    pluginsMap=('Qt53DRenderer sceneparsers'
                'Qt5Declarative qml1tooling'
                'Qt5EglFSDeviceIntegration egldeviceintegrations'
                'Qt5Gui accessible generic iconengines imageformats platforms platforminputcontexts'
                'Qt5Location geoservices'
                'Qt5Multimedia audio mediaservice playlistformats'
                'Qt5Network bearer'
                'Qt5Positioning position'
                'Qt5PrintSupport printsupport'
                'Qt5QmlTooling qmltooling'
                'Qt5Quick scenegraph qmltooling'
                'Qt5Sensors sensors sensorgestures'
                'Qt5SerialBus canbus'
                'Qt5Sql sqldrivers'
                'Qt5TextToSpeech texttospeech'
                'Qt5WebEngine qtwebengine'
                'Qt5WebEngineCore qtwebengine'
                'Qt5WebEngineWidgets qtwebengine'
                'Qt5XcbQpa xcbglintegrations')

    syspluginspath=$(${QMAKE} -query QT_INSTALL_PLUGINS)

    listqtmodules | sort | uniq | \
    while read mod; do
        for module in "${pluginsMap[@]}"; do
            if [[ "$module" != "$mod "* ]]; then
                continue
            fi

            for plugin in ${module#* }; do
                pluginspath=$syspluginspath/$plugin

                if [ ! -e $pluginspath ]; then
                    continue
                fi

                mkdir -p "$libpath/qt/plugins/$plugin"
                cp -rf ${pluginspath}/* "$libpath/qt/plugins/$plugin"
            done
        done
    done
}

qtdeps() {
    qmldeps
    pluginsdeps
}

readdeps() {
    cat "${ROOTDIR}/ports/deploy/linux/$1" | cut -d \# -f 1 | sed '/^$/d' | \
    while read line; do
        echo $line
    done
}

excludedeps() {
    if which pacman 1>/dev/null 2>/dev/null; then
        packages=($(readdeps deps-pkgbuild.txt))

        for package in ${packages[@]}; do
            pacman -Ql $package | grep 'lib.\{1,\}\.so\(\.[0-9]\{1,\}\)\{0,1\}$' | awk '{print $2}' | \
            while read lib; do
                readlink -f $lib
            done
        done
    elif which dpkg-query 1>/dev/null 2>/dev/null; then
        packages=($(readdeps deps-deb.txt))

        for package in ${packages[@]}; do
            dpkg-query -L $package 2>/dev/null | grep 'lib.\{1,\}\.so\(\.[0-9]\{1,\}\)\{0,1\}$' | awk '{print $1}' | \
            while read lib; do
                readlink -f $lib
            done
        done
    elif which rpm 1>/dev/null 2>/dev/null; then
        packages=($(readdeps deps-rpm.txt))

        for package in ${packages[@]}; do
            rpm -ql $package | grep 'lib.\{1,\}\.so\(\.[0-9]\{1,\}\)\{0,1\}$' | awk '{print $1}' | \
            while read lib; do
                readlink -f $lib
            done
        done
    fi
}

isexcluded() {
    lib=$(readlink -f $1)
    exclude=($2)

    for e in ${exclude[@]}; do
        if [[ "$lib" == "$e" ]]; then
            echo 1

            return
        fi
    done

    echo 0
}

solvedeps() {
    path=$1
    echo Installing missing dependencies

    exclude=($(excludedeps | sort | uniq))
    user=$(whoami)
    group=$(ls -ld ~ | awk '{print $4}')
    bundleData=${ROOTDIR}/build/bundle-data

    find ${path} -name 'lib*.so*' -or -name ${APPNAME} | \
    while read libpath; do
        libpath=${libpath/${path}\//}
        fname=$(basename $libpath)
        echo Solving $libpath

        where=${path}/$libpath

        ldd $where | \
        while read lib; do
            if [[ "$lib" == *'=>'* ]]; then
                oldpath=$(echo ${lib/=>/} | awk '{print $2}')
            else
                oldpath=$(echo ${lib} | awk '{print $1}')
            fi

            if [ ! -e "$oldpath" ]; then
                continue
            fi

            e=$(isexcluded "$oldpath" "${exclude[*]}")
            realoldpath=$(readlink -f "$oldpath")

            if [[ "$e" == 1 ]] ||
               [[ "$realoldpath" == /var/lib/VBoxGuestAdditions* ]] ||
               [[ "$realoldpath" == /opt/VBoxGuestAdditions* ]]; then
                continue
            fi

            depbasename=$(basename $oldpath)
            echo '    dep ' $oldpath

            dest=${bundleData}/${APPNAME}/lib

            if [ ! -e ${dest}/$depbasename ]; then
                echo '        copying' "$oldpath"
                cp -f $oldpath ${dest}/
                chmod +x ${dest}/$depbasename
            fi
        done
    done
}

solveall() {
    bundleData=${ROOTDIR}/build/bundle-data
    paths=(${APPNAME}/bin
           ${APPNAME}/lib)

    for path in ${paths[@]}; do
        solvedeps ${bundleData}/$path
    done
}

createlauncher() {
    launcher=${ROOTDIR}/build/bundle-data/${APPNAME}/${APPNAME}.sh

    cat << EOF > "$launcher"
#!/bin/sh

rootdir() {
    dir=\$(dirname \$PWD/\$1)
    cwd=\$PWD
    cd \$dir 1>/dev/null
        echo \$PWD
    cd \$cwd 1>/dev/null
}

ROOTDIR=\$(rootdir \$0)
export LD_LIBRARY_PATH="\${ROOTDIR}"/lib:\$LD_LIBRARY_PATH
export QT_DIR="\${ROOTDIR}"/lib/qt
export QT_QPA_PLATFORM_PLUGIN_PATH=\${QT_DIR}/platforms
export QT_PLUGIN_PATH=\${QT_DIR}/plugins
export QML_IMPORT_PATH=\${QT_DIR}/qml
export QML2_IMPORT_PATH=\${QT_DIR}/qml
#export QT_DEBUG_PLUGINS=1
"\${ROOTDIR}"/bin/${APPNAME} "\$@"
EOF

    chmod +x "$launcher"
}

createportable() {
    pushd "${ROOTDIR}/build/bundle-data"
        version=$(./${APPNAME}/${APPNAME}.sh --version 2>/dev/null | awk '{print $2}')
        arch=$(uname -m)
        tar -cJf "${ROOTDIR}/ports/deploy/linux/${APPNAME}-portable-${version}-${arch}.tar.xz" ${APPNAME}
    popd
}

sources() {
# cat /etc/*-release
# LC_ALL=C pacman -Qo /usr/lib/libm-2.24.so | tr ' ' $'\n' | tail -n 2
    echo
}

detectqtifw() {
    if which binarycreator 1>/dev/null 2>/dev/null; then
        which binarycreator
    else
        ls ~/Qt/QtIFW*/bin/binarycreator 2>/dev/null | sort -V | tail -n 1
    fi
}

createintaller() {
    bincreator=$(detectqtifw)

    if [ -z "$bincreator" ]; then
        return
    fi

    installerDir=${ROOTDIR}/ports/installer
    dataDir=${installerDir}/packages/com.webcamoidprj.webcamoid/data

    mkdir -p "${dataDir}"
    cp -rf \
        ${ROOTDIR}/build/bundle-data/${APPNAME}/* \
        ${dataDir}

    pushd "${ROOTDIR}/build/bundle-data/${APPNAME}"
        version=$(./${APPNAME}.sh --version 2>/dev/null | awk '{print $2}')
    popd

    arch=$(uname -m)

    ${bincreator} \
         -c ${installerDir}/config/config.xml \
         -p ${installerDir}/packages \
         ${ROOTDIR}/ports/deploy/linux/${APPNAME}-${version}-${arch}.run

    rm -rf ${dataDir}
}

package() {
    createportable
    createintaller
}

prepare
qtdeps
solveall
createlauncher
package