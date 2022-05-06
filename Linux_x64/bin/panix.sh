#!/bin/sh
################################################################################
# Product:		ProactivaNET
# Application:	EspiralMS.ProactivaNET.PanixAgent
#
# File:			panix.sh
# Description:	Bash script for launching panix.pl
# 
# Author:		equipossaa@espiralms.com
# 
# Date: 	2021-07-29
# Version:	01.07.00.00
#
################################################################################
#
# Comments: Uncompresses package and invokes panix.pl
#
################################################################################
################################################################################
# GLOBAL CONSTANTS
################################################################################

VERSION="1.7.0.0"				# Versión del script
AGENTDIRECTORY="PanixPackage"	# Directorio del agente
AGENTLAUNCHER="panix.pl"		# Nombre del launcher del agente
VERSIONFILE="_v${VERSION}"		# Nombre del fichero con version del paquete
PACKAGEDIR="panix_temp"			# Nombre del directorio donde se va a trabajar
################################################################################
# GLOBAL VARIABLES
################################################################################

SHOWHELP=0						# Indica si hay que mostrar la ayuda
SHOWVERSION=0					# Indica si hay que mostrar la versión
PACKAGE=""						# Nombre del paquete a utilizar
EXTRACT_PACKAGE=1				# Indica si hay que extraer el paquete o no.
SERVER=""						# URL del inbox a donde enviar la auditoría
OUTPUTDIRECTORY=""				# Directorio donde dejar la auditoría
WORKINGDIR="`pwd`/${PACKAGEDIR}"	# Directorio de trabajo
VERBOSITYLEVEL=0				# Nivel de verbosidad
UNCOMPRESSZIPVERBOSITY="-q"		# Indica la verbosidad para la descompresión de zip
UNCOMPRESSTARVERBOSITY=""		# Inidica la verbosidad para la descompresión de tar
NOCOMPRESSION=""				# Indica si no se comprime la auditoria a enviar
AGENTSERVERPARAMETER=""			# Parámetro para pasarle el server al agente.
AGENTDIRECTORYPARAMETER=""		# Parámetro para pasarle el directorio al agente.
AGENTWORKINGDIRPARAMETER=""		# Parámetro para pasarle el directorio de trabajo al agente.
AGENTVERBOSITYPARAMETER=""		# Parámetro para pasarle la verbosidad al agente.
AGENTSENDALLAUDITSTOINBOX=0		# Parametro para indicar que se van a enviar todas las auditorias almacenadas al inbox
AGENTPATHAUDITS=""				# Parametro para pasarle la ruta de las auditorias a enviar.
UTILS=0							# Indica si ya adjuntamos funciones de Utileria

################################################################################
# FUNCTIONS
################################################################################

################################################################################
# Funcion que muestra la ayuda
################################################################################
ShowUsage()
{
	echo "Usage ${0} [-p=<agent package>|--package=<agent package>] [-s=<url inbox>|--server=<url inbox>] [-l=<audit destination path>|--local=<audit destination path>] [-d=<working directory>|--directory=<working directory>] [-dne|--dne] [-v=<level>|--verbose=<level>] [-V|--version] [-h|--help] [-i=<pat_audits>|--in=<pat_audits>]"
	echo "Where:"
	echo "    -p | --package, is the agent's full package name to be used (e.g Panix_01.02.00.00_Linux_x64.tar.gz)."
	echo "    -s | --server, is the url inbox where audit should be sended."
	echo "    -l | --local, is the local directory where audit should be stored."
	echo "    -d | --directory, is the working directory, `pwd`/panix_temp by default."
	echo "    -dne | --dne, Do not extract, if any packages has been extracted before, it does not extract again."
	echo "    -v | --verbose, to indicate verbosity level; 0 -> Error, 1 -> Warning, 2 -> Info, 3 -> Debug."
	echo "    -V | --version, shows this script version."
	echo "    -h | --help, show this help."
	echo "    -i | --in, send All audits in specified folder to inbox. --server parameter is necesary"
	echo "    -C | --no-compression to send audit uncompressed"
}

################################################################################
# Funcion que muestra la versión 
################################################################################
ShowVersion()
{
	echo "Panix agent launcher for Unix and Linux ${VERSION}"
}


################################################################################
# Funcion que imprime un mensaje en función de
# de la verbosidad.
# Parámetros:
# Nivel 0 -> Error, 1 -> Warning, 2 -> Info, 3 -> Debug
# Mensaje
################################################################################
PrintMessage()
{
	if [ $1 -le $VERBOSITYLEVEL ]
	then
		PREFIX=""
		case $1 in
			"0")
				PREFIX="[ERROR]"
				;;
			"1")
				PREFIX="[WARNING]"
				;;
			"2")
				PREFIX="[INFO]"
				;;
			"3")
				PREFIX="[DEBUG]"
				;;
		esac
		echo "${PREFIX} $2"

	fi
}


################################################################################
# Funcion que devuelve si un string tiene espacios en blanco
################################################################################
HaveWhiteSpaces() 
{
	VALUE=$1
	case "$VALUE" in
		*\ * )
			echo "1"
			;;
		*)
			echo "0"
			;;
	esac
}

################################################################################
# Funcion que devuelve el path absoluto de un fichero
################################################################################
getABsolutePathFile()
{
	F_FILE=$1
	F_PWD=`pwd`

	case $F_FILE in
		/*) 
			echo "$F_FILE" 
			;;
		*) 
			echo "${F_PWD}/${F_FILE}" 
			;;
	esac
}

################################################################################
# Funcion que parsea los parámetros recibidos.
################################################################################
ParseArgv()
{
	while [ "X$#" != "X0" ]
	do
		PARAMETER=$1
		KEY=`echo ${PARAMETER} | cut -d = -f 1`
		VALUE=`echo ${PARAMETER} | cut -d = -f 2`
		case ${KEY} in
			"-p" | "--package")
				PACKAGE=${VALUE}
				;;
			"-s" | "--server")
				SERVER=${VALUE}
				AGENTSERVERPARAMETER=${PARAMETER}
				;;
			"-l" | "--local")
				OUTPUTDIRECTORY=${VALUE}
				AGENTDIRECTORYPARAMETER=${PARAMETER}
				;;
			"-d" | "--directory")
				WORKINGDIR="${VALUE}/${PACKAGEDIR}"
				AGENTWORKINGDIRPARAMETER="-d=${WORKINGDIR}"
				;;
			"-dne" | "--dne")	
				EXTRACT_PACKAGE=0
				;;
			"-v" | "--verbose")
				VERBOSITYLEVEL=${VALUE}
				AGENTVERBOSITYPARAMETER=${PARAMETER}
				# Si la verbosidad es igual o mayor a WARNING, extraemos el paquete con verbosidad
				if [ ${VERBOSITYLEVEL} -ge 2 ]
				then
					UNCOMPRESSTARVERBOSITY="v"
					UNCOMPRESSZIPVERBOSITY=""
				fi
				;;
			"-V" | "--version")
				SHOWVERSION=1
				;;
			"-h" | "--help")
				SHOWHELP=1
				;;
			"-i" | "--in")
				AGENTPATHAUDITS=${VALUE}
				AGENTSENDALLAUDITSTOINBOX=1
				AGENTPATHAUDITSTOINBOXPARAMETER=${PARAMETER}
				;;
			"-C" | "--no-compression")
				NOCOMPRESSION="-C"
				;;
		esac
		shift
	done
}

################################################################################
# Funcion que parsea los parámetros recibidos.
################################################################################
PrintConfig()
{
	PrintMessage 2 ""
	PrintMessage 2 "Configuration received:"
	PrintMessage 2 " Package: ${PACKAGE}"
	PrintMessage 2 " Server: ${SERVER}"
	PrintMessage 2 " Directory: ${OUTPUTDIRECTORY}"
	PrintMessage 2 " Working directory: ${WORKINGDIR}"
	PrintMessage 2 " Verbosity level: ${VERBOSITYLEVEL}"
	PrintMessage 2 " Audits Path Send to inbox : ${AGENTPATHAUDITS}"
	PrintMessage 2 ""
}


################################################################################
# Funcion que comprueba que la version del paquete coincida con la del launcher
# return: 0 si ok, 1 si ko
################################################################################
CheckPackageVersion()
{
	if [ ! -f ${WORKINGDIR}/${VERSIONFILE} ]; then
		return 1
	else
		return 0
	fi
}

################################################################################
# Funcion que extrae el paquete manteniendo los plugins que pueda tener
# Recive: ruta paquete
################################################################################
ExtractPackage()
{
	if [ ! -f ${PACKAGE} ]; then
		PrintMessage 0 "Package ${PACKAGE} does not exist."
		exit 1
	fi

	# Realizar copia de los plugins
	if [ -d ${WORKINGDIR}/plugins ]; then
		PrintMessage 2 "Making copy of the plugins directory"
		cp -rp ${WORKINGDIR}/plugins ${WORKINGDIR}/../plugins.bak
	fi

	# Vaciar directorio de trabajo si existe y sino crearlo
	if [ -d ${WORKINGDIR} ]; then
		PrintMessage 2 "Working directory ${WORKINGDIR} exits. It will emptied."
		rm -fr ${WORKINGDIR}/*
	else
	        PrintMessage 2 "Working directory ${WORKINGDIR} does not exist. It will be created."
        	mkdir -p ${WORKINGDIR}
	fi

	# Desempaquetar
	PACKAGE_EXT=`echo ${PACKAGE}| awk -F. '{print $NF}'`
	EXTRACTMETHOD=0

	PrintMessage 2 "Extracting package"

	if [ "X${PACKAGE_EXT}" = "Xzip" ] || [ "X${PACKAGE_EXT}" = "XZIP" ]; then
		PrintMessage 3 "unzip ${UNCOMPRESSZIPVERBOSITY} -o ${PACKAGE} -d ${WORKINGDIR}"
		unzip ${UNCOMPRESSZIPVERBOSITY} -o ${PACKAGE} -d ${WORKINGDIR}
		EXTRACTMETHOD=1
	else
		# Al cambiar de directorio es necesario obtener la ruta absoluta
		ABSPATHPACKAGE=`getABsolutePathFile "${PACKAGE}"`
		PrintMessage 3 "gzip -cd ${ABSPATHPACKAGE} |tar xf${UNCOMPRESSTARVERBOSITY} -"
		MYPWD=`pwd`
		cd ${WORKINGDIR}
		# Metodo compatible con tar de GNU y tar de HPUX
		gzip -cd ${ABSPATHPACKAGE} |tar xf${UNCOMPRESSTARVERBOSITY} -
		cd ${MYPWD}
		EXTRACTMETHOD=2
	fi

	# Si hubo algun problema en la extraccion de la extension del package, extraemos con ambos  metodos
	if [ "X${EXTRACTMETHOD}" = "X0" ]; then
		PrintMessage 3 "Last chance to extract, both methods"
		unzip ${UNCOMPRESSZIPVERBOSITY} -o ${PACKAGE} -d ${WORKINGDIR}
		# Al cambiar de directorio es necesario obtener la ruta absoluta
		ABSPATHPACKAGE=`getABsolutePathFile "${PACKAGE}"`
		MYPWD=`pwd`
		cd ${WORKINGDIR}
		gzip -cd ${ABSPATHPACKAGE} |tar xf${UNCOMPRESSTARVERBOSITY} -
		cd ${MYPWD}
	fi

	# Restaurar plugins
	PrintMessage 2 "Restore plugins directory"
	# Si hay copia de plugins y no es vacia
	if [ -d ${WORKINGDIR}/../plugins.bak/ ] && [ ! -z "$(ls -A ${WORKINGDIR}/../plugins.bak/)" ]; then
		for plugin in `ls ${WORKINGDIR}/../plugins.bak/`
		do
			# No se puede usar -e en Solaris, emplear -f y -d en su lugar
			if [ ! -f ${WORKINGDIR}/plugins/${plugin} ] && [ ! -d ${WORKINGDIR}/plugins/${plugin} ]; then
				cp -rp ${WORKINGDIR}/../plugins.bak/${plugin} ${WORKINGDIR}/plugins/
			fi
		done
	fi
	if [ -d ${WORKINGDIR}/../plugins.bak ]; then
		rm -fr ${WORKINGDIR}/../plugins.bak
	fi
}


################################################################################
# MAIN 
################################################################################

# Verificamos que tenemos los parámetros mínimos para la ejecución
if [ $# -lt 1 ]
then
	ShowUsage
	exit 1
fi

# Validamos datos de entrada
RESULT=0
F_RESULT=`HaveWhiteSpaces "${WORKINGDIR}"`
if [ "X${F_RESULT}" != "X0" ]
then
	RESULT=1
	PrintMessage 0 "Execution directory can't contain whitespaces"
fi
for VAR in "$@"
do
	PARAMETER=$VAR
	KEY=`echo ${PARAMETER} | cut -d = -f 1`
	VALUE=`echo ${PARAMETER} | cut -d = -f 2`
	case ${KEY} in
		"-p" | "--package")
			F_RESULT=`HaveWhiteSpaces "${VALUE}"`
			if [ "X${F_RESULT}" != "X0" ]
			then
				RESULT=1
				PrintMessage 0 "Package can't contain whitespaces"
			fi
			;;
		"-l" | "--local")
			F_RESULT=`HaveWhiteSpaces "${VALUE}"`
			if [ "X${F_RESULT}" != "X0" ]
			then
				RESULT=1
				PrintMessage 0 "Directory where audit should be stored can't contain whitespaces"
			fi
			;;
		"-d" | "--directory")
			F_RESULT=`HaveWhiteSpaces "${VALUE}"`
			if [ "X${F_RESULT}" != "X0" ]
			then
				RESULT=1
				PrintMessage 0 "The working directory can't contain whitespaces"
			fi
			;;
		"-i" | "--in")				
			F_RESULT=`HaveWhiteSpaces "${VALUE}"`
			if [ "X${F_RESULT}" != "X0" ]
			then
				RESULT=1
				PrintMessage 0 "Directory with audits to send can't contain whitespaces"
			else
				# Se comprueba que no haya auditorias para procesar con espacios en blanco
				for F_AUDIT in ${VALUE}/*
				do
					F_RESULT=`HaveWhiteSpaces "${F_AUDIT}"`
					if [ "X${F_RESULT}" != "X0" ]
					then
						RESULT=1
						PrintMessage 0 "Audits files to send can't contain whitespaces"
					fi
				done
			fi
			;;
	esac
done

if [ "X${RESULT}" != "X0" ]
then
	exit 1
fi

# Parseamos la entrada
ParseArgv $@

# Si tenemos el flag de mostrar ayuda, la mostramos y salimos.
if [ "X${SHOWHELP}" = "X1" ]
then
	ShowUsage
	exit 0
fi

# Si tenemos el flag de mostrar versión, la mostramos y salimos.
if [ "X${SHOWVERSION}" = "X1" ]
then
	ShowVersion
	exit 0
fi

# Mostramos la línea de invovación y la configuración que vamos a utilizar.
PrintConfig

CONTINUETOAUDIT=1
# Si no hemos recibido un nombre de package y no se usa el parametro dne, mensaje de error y salimos. 
if [ "X${PACKAGE}" = "X" ] && [ "X${EXTRACT_PACKAGE}" = "X1" ]
then
	PrintMessage 0 "A package is needed to continue."
	CONTINUETOAUDIT=0
fi

# Si no recibimos un servidor o un directorio donde dejar la auditoría, mensaje de error y salimos
if [ "X${SERVER}" = "X" ] && [ "X${OUTPUTDIRECTORY}" = "X" ]
then
	PrintMessage 0 "Either a server or a directory to leave the audit is needed to continue."
	CONTINUETOAUDIT=0
fi

# Si la auditoria se guadará localmente comprobamos que exista el directorio de salida
# Si no existe se crea el directorio de salida.
if [ "X${OUTPUTDIRECTORY}" != "X" ]
then
	if [ ! -d ${OUTPUTDIRECTORY} ]
	then		
		PrintMessage 2 "Output directory ${OUTPUTDIRECTORY} does not exist. It will be created"
		mkdir -p ${OUTPUTDIRECTORY};		
	fi
fi


# Si recibimos path de auditorias y no url del inbox salimos
if [ "X${AGENTSENDALLAUDITSTOINBOX}" != "X0" ] && [ "X${SERVER}" = "X" ]
then
	PrintMessage 0 "Inbox url is nedeed."
	CONTINUETOAUDIT=0
fi

# Si nos falto algún parámetro obligatorio salimos.
if [ "X${CONTINUETOAUDIT}" = "X0" ]
then
	exit 1
fi

# Si no existe el directorio de trabajo, lo creamos
if [ ! -d ${WORKINGDIR} ]; then
	PrintMessage 2 "Working directory ${WORKINGDIR} does not exist. It will be created"
	mkdir -p ${WORKINGDIR}
fi

# Extrayendo el paquete si es necesario.
if [ "X${EXTRACT_PACKAGE}" = "X1" ]; then
	PrintMessage 2 "Evaluating conditions to extract package."

	# Comprobar version
	CheckPackageVersion
	# Si la version no es la misma se extrae
	if [ $? -ne 0 ]; then
		ExtractPackage ${PACKAGE}
	fi
else
	# Si se ha invocado con el parámetro --dne, no es necesario extraer el paquete.
	PrintMessage 2 "Panix package will not be extracted, looking for previous packages."

	# Si no existe el panix_temp/panix.pl se lanza un error.
	if [ ! -f ${WORKINGDIR}/${AGENTLAUNCHER} ]; then
		PrintMessage 0 "Error using parameter --dne. No previous extracted package has been found, ${WORKINGDIR}/${AGENTLAUNCHER} does not exist."
		exit 1
	fi
fi

# Comprobar version package descomprimido
CheckPackageVersion
if [ $? -eq 0 ]; then
	PrintMessage 2 "Panix Launcher and Panix Package are the correct version."
else
	PrintMessage 0 "Panix Launcher and Panix Package differs."
	exit 1
fi

# Garantizamos permisos de ejecución en el directorio de trabajo.
chmod -R 755 ${WORKINGDIR}/PanixAgent/

# Exportamos las varibles necesarias para ejecutar el perl interno del paquete. 
# Invocamos el export-perl-env.sh en el mismo proceso para tener las variables disponibles en toda la ejecución.
. ${WORKINGDIR}/PanixAgent/export-perl-env.sh

# Comprobar librerias dinamicas y copiarlas si no estan disponibles
PrintMessage 2 "GetLibrariesFromFile ${WORKINGDIR}/PanixAgent/perl/bin/perl 1"
GetLibrariesFromFile ${WORKINGDIR}/PanixAgent/perl/bin/perl 1
RETVAL=$?
if [ $RETVAL = -1 ]; then
	PrintMessage 0 "Missing libraries"
	exit 1
fi

# Invocamos al launcher
if [ ! -f ${WORKINGDIR}/${AGENTLAUNCHER} ]; then
	PrintMessage 0 "${AGENTLAUNCHER} does not exist in ${WORKINGDIR}/${AGENTDIRECTORY}. Cannot invoke agent."
	exit 1
fi
LAUNCHSTR="${WORKINGDIR}/PanixAgent/perl/bin/perl ${WORKINGDIR}/${AGENTLAUNCHER} -sv=${VERSION} ${AGENTSERVERPARAMETER} ${AGENTDIRECTORYPARAMETER} ${AGENTWORKINGDIRPARAMETER} ${AGENTVERBOSITYPARAMETER} ${AGENTSENDALLAUDITSTOINBOX} ${AGENTPATHAUDITSTOINBOXPARAMETER} ${NOCOMPRESSION}"
PrintMessage 2 "${LAUNCHSTR}"
${WORKINGDIR}/PanixAgent/perl/bin/perl ${WORKINGDIR}/${AGENTLAUNCHER} -sv=${VERSION} ${AGENTSERVERPARAMETER} ${AGENTDIRECTORYPARAMETER} ${AGENTWORKINGDIRPARAMETER} ${AGENTVERBOSITYPARAMETER} ${AGENTPATHAUDITSTOINBOXPARAMETER} ${NOCOMPRESSION}
