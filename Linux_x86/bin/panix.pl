#!/usr/bin/perl -w

################################################################################
# Product:	ProactivaNET
# Application:	EspiralMS.ProactivaNET.PanixAgent
#
# File:		panix.pl
# Description:	Perl script for launching OCS and FusionInventory Agents.
#		It launches either OCS or FusionInventory Agent with plugins.
# 
# Author:	equipossaa@espiralms.com
# 
################################################################################
#
# Comments: Launches agent and plugins from the agent package or from general
#	    directory in disk
#
################################################################################

use strict;
use warnings;
use Switch;
use File::Path qw(make_path remove_tree);
use IO::Compress::Gzip qw(gzip $GzipError) ;

#---------------------------------------------------------------------------------
# VARS
#---------------------------------------------------------------------------------

my $launchdir = `pwd`;
chomp($launchdir);
my $basedir = `pwd`;
chomp($basedir);
$basedir .= "/panix_temp";
my $workingdir = $basedir . "/PanixAgent";
my $agent = "fusioninventory-agent"; 
my $injector = "fusioninventory-injector";
my ($wgetAvailable, $curlAvailable, $lynxAvailable );
my $version = "";
my $debug = 0;
my $dstdir = undef;
my $urlinbox = undef;
my $nocompression = undef;
my $pluginsOut = "";
my $verboseagent = "2>/dev/null";
my $verboseplugin = "2>/dev/null";
my $verboseInjector = "";
my $pathaudits = undef;

#---------------------------------------------------------------------------------
#MAIN
#---------------------------------------------------------------------------------

# Primero obtenemos la version que se ha de pasar como parametro
$version = GetVersion(@ARGV);

# parametros
if(scalar(@ARGV)) {
	if($ARGV[0] =~ /-V/ || $ARGV[0] =~ /--version/i) {	# -V | --version -> 	Mostrar version
		ShowVersion();
		exit 1;
	} elsif ($ARGV[0] =~ /-h/i || $ARGV[0] =~ /--help/i) {	# -h | --help 	 -> 	Mostrar ayuda.
		ShowHelp();
		exit 1;
	}
} 
else{
	ShowHelp(); 
	exit 1;
}



# parseamos la línea de parámetros.
ParseArgv(@ARGV);

my $audit;
#Si se han de enviar de forma masiva no se audita
if (!defined($pathaudits))
{
	TraceInfo("Launching Perl agent...");
	# Lanzamos el agente inventariador

	# [PANIX REFACTORED]
	# User Story 22409: Fichero de auditorias temporales vinculadas al equipo
	# Definimos directorio temporal unico para evitar interbloqueos
	my $hostname = `hostname`;
	chomp($hostname);
	my ($year, $month, $day, $hour, $min, $sec) = (localtime(time))[5, 4, 3, 2, 1, 0];
	my $date = sprintf "%02d-%02d-%02d-%02d-%02d-%02d", ($year+1900), ($month+1), $day, $hour, $min, $sec;
	my $uniqPathAudit = $workingdir . "/" . $hostname . "_" . $date;
	TraceInfo("Create unique path for audit: $uniqPathAudit");
	if ( !-d $uniqPathAudit ) {
		make_path $uniqPathAudit or die $!;
	}

	#Cambiamos a directorio de trabajo para ejecutar componentes de panix
	chdir $workingdir;
	TraceInfo("$workingdir/perl/bin/perl $workingdir/perl/bin/$agent -l $uniqPathAudit $verboseagent  -- --conf-file=$workingdir/agent.cfg ");
	`$workingdir/perl/bin/perl $workingdir/perl/bin/$agent -l $uniqPathAudit $verboseagent  --conf-file=$workingdir/agent.cfg`;
	my $resultFile = `ls $uniqPathAudit/*.ocs 2>/dev/null`;
	chomp($resultFile);
	TraceInfo("Agent executed. Result file is: " . $resultFile);
	if ($resultFile =~ /^$/) {
		TraceError("Agent execution failed, there is no audit file. Exiting.");
		exit 1;
	}

	# Lanzamos los plugins, cuidando de no lanzar repetidos
	my @pluginsAlreadyRun = ();

	RunPlugins($basedir . "/plugins", \@pluginsAlreadyRun);
	RunPlugins("/etc/ocsinventory/panetPlugins", \@pluginsAlreadyRun);

	# Juntamos la auditoría
	$audit = `cat $resultFile`;
	$pluginsOut.="<\/CONTENT>";
	$audit =~ s/<\/CONTENT>/$pluginsOut/;
	SaveFile($resultFile, $audit);

	# Guardamos la auditoria
	# Primero si hay que subirla
	if ( ! defined($dstdir)){
		# Comprimirla si no se indica lo contrario
		if ( !defined($nocompression) ) {
			gzip $resultFile => "$resultFile.gz" or die "Gzip filed: $GzipError\n";
			$resultFile .= ".gz";
			TraceInfo("Compress audit in file: ". $resultFile);
		}
		UploadAuditFile($resultFile);
		# volvemos a directorio de ejecucion
		chdir($launchdir);
	}
	# si la tenemos que dejar en local
	else {
		# volvemos a directorio de ejecucion
	chdir $launchdir;
		my $dstfile = $dstdir . "/" . $hostname . "_" . $date . ".xml";
		TraceInfo("Saving audit in file " . $dstfile);
		SaveFile($dstfile, $audit);
	}
	unlink($resultFile);
	rmdir($uniqPathAudit);
	# [/PANIX REFACTORED]

}
else
{
	if (defined($urlinbox))
	{
		TraceInfo("Se envian auditorias desde " . $pathaudits . " al INBOX");
		UploadAllAuditFile();
	}
	else{
		TraceInfo("Can not upload all files because no url_inbox defined.");
	}
}


#---------------------------------------------------------------------------------
# SUBROUTINES
#---------------------------------------------------------------------------------
# --------------------------------------------------------------------------------
# Parse parameters
sub ParseArgv {
	my @parameters = @_;
	for (my $i = 0; $i < @parameters; $i++)	{
		my ($key, $value) = split(/=/, $parameters[$i]);		
		if ($key =~ /-s/i || $key =~ /--server/i){
			$urlinbox = $value;
		} elsif ($key =~ /-l/i || $key =~ /--local/i){
			$dstdir = $value;
		} elsif ($key =~ /-v/ || $key =~ /--verbose/i){
			$debug = $value;
			if ($debug >= 2){
				$verboseagent=" --debug";
				$verboseInjector=" --verbose";
				$verboseplugin="";
			}
		} elsif ($key =~ /-d/i || $key =~ /--directory/i){ 
			$basedir = $value;
			$workingdir = $basedir . "/PanixAgent";
		} elsif ($key =~ /-i/i || $key =~ /--in/i)	{
			$pathaudits = $value;
		} elsif ($key =~ /-C/i || $key =~ /--no-compression/i) {
			$nocompression=1;
		} elsif ($key =~ /-sv/i || $key =~ /--setVersion/i)	{
			$version = $value;
		} else {
			TraceError("Unknown key " . $key);
		}
	}
}	

# --------------------------------------------------------------------------------
# Save file
sub SaveFile{
	my ($file, $content) = @_;
	open(my $fd, '>', $file);
	print $fd $content;
	close $fd;
}

# --------------------------------------------------------------------------------
# Run plugins
sub RunPlugins {
	my ($pluginDir, $pluginsAlreadyRun) = @_;
	TraceInfo("Looking in " . $pluginDir . " directory for plugins.");
	if (!-d $pluginDir){
		TraceWarning($pluginDir . " does not exist.");
		return;
	}
	my @pluginFiles;
	if(opendir(DIR,$pluginDir))
	{
		@pluginFiles = readdir(DIR);
		closedir(DIR);
	}
	else
	{
		TraceError("Could not open plugins directory: " . $pluginDir . " " . $!);
		return;
	}
	my $PANET_PLUGIN_LAYER_VERSION = $version;
	my $PANET_PLUGIN_LAYER_VERSION_XML = "<PANET_PLUGINS><VERSION>$PANET_PLUGIN_LAYER_VERSION</VERSION>{plugins}</PANET_PLUGINS>";
	my $PANET_PLUGIN_LAYER_ERROR_XML = "<PLUGIN><PATH>{path}</PATH><ERROR>{error}</ERROR></PLUGIN>";
	my $output="";
	my $error="";
	my $pluginError="";
	my $pluginErrorXml="";
	my $pluginXml = $PANET_PLUGIN_LAYER_VERSION_XML;
	my $pluginOutput = "";
	foreach (@pluginFiles)
	{
		my $pluginName = $_;
		
		if (!grep(/^$pluginName$/, @$pluginsAlreadyRun))
		{
			push(@$pluginsAlreadyRun, $pluginName);

			my $plugin = $pluginDir . "/" . $pluginName;
			`chmod 0755 $plugin`;
			-d $plugin && next;
			
			TraceDebug("\trunning plugin $plugin ...");
		
			# execute plugin
			$pluginError = $PANET_PLUGIN_LAYER_ERROR_XML;
			{
				$output = `$workingdir/perl/bin/perl $plugin $verboseplugin`;
				# Parseamos para escapar caracteres especiales.
				$output = EscapeXMLValue($output);
				TraceInfo($output);
			}
			if ($output eq /^$/)
			{
				$error = $!;
				if ($error !~ /^$/){
					TraceError($error);
				}
			}
			$pluginError =~ s/{error}/$error/;
			$pluginError =~ s/{path}/$plugin/;
			$pluginErrorXml .= $pluginError;
			$pluginOutput .= $output;
			$pluginOutput =~ s/<REQUEST><CONTENT>//;
			$pluginOutput =~ s/<\/CONTENT><\/REQUEST>//;
		}
	}
	$pluginXml =~ s/{plugins}/$pluginErrorXml/;
	$pluginXml .= $pluginOutput;
	$pluginsOut .= $pluginXml;
	TraceInfo("End running plugins in " . $pluginDir);
}

# --------------------------------------------------------------------------------
# Get wich alternative upload methods are available and get paths
sub GetAlternativeUploadMethods{
	TraceInfo("Getting altertantive upload methods if are available.");
	my $result = 0;
	my $systemPath = $ENV{PATH};
	my @checkPaths = split(/:/, $systemPath);
	# Se busca cada metodo en todos los paths de PATH y si existe el binario se almacenan en su metodo
	foreach my $path (@checkPaths){
		TraceInfo("Checking for executables in " . $path);
		if ( -e $path."/wget") {
			TraceInfo("Wget executable found in " . $path);
			$wgetAvailable .= $path."/wget".":";
		}
		if ( -e $path."/curl") {
			TraceInfo("Curl executable found in " . $path);
			$curlAvailable .= $path."/curl".":";
		}
		if ( -e $path."/lynx") {
			TraceInfo("Lynx executable found in " . $path);
			$lynxAvailable .= $path."/lynx".":";
		}
	}
	# Eliminar : finales
	if ( $wgetAvailable ) { $wgetAvailable =~ s/:$//g; }
	if ( $curlAvailable ) { $curlAvailable =~ s/:$//g; }
	if ( $lynxAvailable ) { $lynxAvailable =~ s/:$//g; }
	
	$result;
}

# --------------------------------------------------------------------------------
# Execute upload method
sub ExecAlternativeUploadMethod{
	my $result = 0;
	my ( $method, $auditFile, $methodBinaries_str ) = @_;
	TraceInfo("Execute upload method ".$method.".");
	my @methodBinaries = split /:/, $methodBinaries_str;
	
	switch( $method ) {
		case "curl" {
			foreach ( @methodBinaries ) {
				TraceInfo("Trying upload with curl.");
				my $outputCurl;
				if ( $auditFile =~ /\.gz$/i ) {
					TraceInfo("Audit compressed in gzip format.");
					$outputCurl = `$_ -k -F "file=\@$auditFile" -A 'ocs' $urlinbox -w '%{http_code}\n' -o /dev/null -s -H "Content-Type:Application/gzip" -H "Content-Encoding:gzip" 2>&1`;
				} else {
					$outputCurl = `$_ -k -F "file=\@$auditFile" -A 'ocs' $urlinbox -w '%{http_code}\n' -o /dev/null -s 2>&1`;
				}
				chomp($outputCurl);
				TraceInfo($outputCurl);
				# Nos devuelve el codigo HTTP
				if ($outputCurl =~ /200/){
					TraceInfo("Successfuly uploaded with curl: $_");
					`rm -f $auditFile`;
					last;
				}
				else {
					TraceInfo("Failed curl upload.");
				}
			}
		}
		case "wget" {
			foreach ( @methodBinaries ) {
				TraceInfo("Trying upload with wget.");
				my $outputWget;
				if ( $auditFile =~ /\.gz$/i ) {
					TraceInfo("Audit compressed in gzip format.");
					$outputWget = `$_ --no-check-certificate -U ocs --post-file=$auditFile --server-response $urlinbox -O /dev/null  --header "Content-Type:Application/gzip" --header "Content-Encoding:gzip" 2>&1`;
				} else {
					$outputWget = `$_ --no-check-certificate -U ocs --post-file=$auditFile --server-response $urlinbox -O /dev/null 2>&1`;
				}
				TraceInfo($outputWget);
				# Tenemos todas las cabeceras de la respuesta y buscamos el 200 OK.
				if ($outputWget =~ m/200 OK/) {
					TraceInfo("Successfuly uploaded with wget: $_");
					`rm -f $auditFile`;
					last;
				}
				else {
					TraceInfo("Failed wget upload.");
				}
			}
		}
		case "lynx" {
			foreach ( @methodBinaries ) {
				my $lynxFile = $basedir."/lynx.file";
				TraceInfo("Trying upload with lynx.");
				# Lynx no soporta en envio de auditorias comprimidas
				if ( $auditFile =~ /\.gz$/i ) {
					TraceInfo("Failed lynx upload: not support sending compressed audits.");
				} else {
				`cat $auditFile | $_ --post_data -useragent=ocs $urlinbox --error_file=$lynxFile 1>/dev/null 2>&1`;
				# Escribe las cabeceras a un fichero y buscamos el 200 OK
				my $lynxError = `cat $lynxFile | grep "200 OK" | wc -l`;
				`rm -f $lynxFile`; # Hay que borrar el fichero porque lynx apenda en lugar de recrear.
				if ($lynxError == 1){
					TraceInfo("Successfuly uploaded with lynx: $_");
					`rm -f $auditFile`;
					last;
				}
				else{
					TraceInfo("Failed lynx upload.");
				}
			}
		}
	}
	}
	
	$result;
}

# --------------------------------------------------------------------------------
# Upload audit file
# Optional paramater: filePath
sub UploadAuditFile{
	# [PANIX REFACTORED]
	# User Story 22409: Fichero de auditorias temporales vinculadas al equipo
	# Orden metodos envio: curl, wget, fusion-injector, lynx
	TraceInfo("Trying upload audit file.");

	my $filePath = shift;
	# Si no se recibe parametro o no existe fiechero: la auditoria se obtiene de memoria (variable audit)
	if ( ! defined($filePath) || ! -e $filePath ) {
		# Tenemos que guardar la auditoría en un fichero temporal
		# al intentar enviar el contenido de memoria se queja el shell 
		# por el tamaño del contenido de la variable.
		my $filePath = $basedir."/tmp.ocs";
		SaveFile($filePath, $audit);
	}		
	# [/PANIX REFACTORED]

	# Buscamos que metodos alternativos tenemos entre wget, curl y lynx
	GetAlternativeUploadMethods();
	
	# Intentamos con curl
	if ( -e $filePath && $curlAvailable ) {
		ExecAlternativeUploadMethod("curl",$filePath,$curlAvailable);
	}
	# Intentamos con wget
	if ( -e $filePath && $wgetAvailable ){
		ExecAlternativeUploadMethod("wget",$filePath,$wgetAvailable);
	}
	# Intentamos con fusion-injector
	my $injectorPath = $workingdir."/perl/bin/".$injector;
	if ( -e $filePath && -e $injectorPath ){
		# [PANIX REFACTORED]
		# User Story 23906: Soportar envío auditorías comprimidas
		# Se pasa la auditoria sin comprimir ya que fusion-injector la comprime internamente
		my $filePahtInjector = $filePath;
		$filePahtInjector =~ s/.gz$//g;
		my $uploadOutput = undef;
		if( defined($nocompression) ) {
			# Envio sin comprimir
			$uploadOutput = `$workingdir/perl/bin/perl $injectorPath $verboseInjector --no-ssl-check --file $filePahtInjector --url $urlinbox --remove --no-compression`;
		} else {
			# Envio normal (comprimido con injector)
			$uploadOutput = `$workingdir/perl/bin/perl $injectorPath $verboseInjector --no-ssl-check --file $filePahtInjector --url $urlinbox --remove`;
		}
		TraceInfo($uploadOutput);
		if ( -e $filePahtInjector ) {
			TraceInfo("Failed fusioninventory injector upload");
		}
		else{
			TraceInfo("Successfuly uploaded with fusioninventory injector.");
			# Borrar el fichero gz
                        if ( -e $filePath ) {
                                unlink $filePath;
                        }
		}
		# [/PANIX REFACTORED]
	}
	# Intentamos con lynx
	if ( -e $filePath && $lynxAvailable ){
		ExecAlternativeUploadMethod("lynx",$filePath,$lynxAvailable);
	}
	
	# Si no pudimos subir el fichero, lo borramos.
	if (-e $filePath){
		TraceInfo("Failed upload audit file.");
		`rm -f $filePath`;
	}
	else {
		TraceInfo("OK upload audit file.");
	}	
}

# --------------------------------------------------------------------------------
# Upload audit file
sub UploadAllAuditFile{
	# Orden metodos envio: curl, wget, fusion-injector, lynx
	TraceInfo("Start sending all audits");
	
	opendir(DIR, $pathaudits) or die $!; #se abre el directorio
	my @files = grep(!/^\./,readdir(DIR));
	closedir(DIR);
	my $filePath = "";
	
	# Buscamos que metodos alternativos tenemos entre wget, curl y lynx
	GetAlternativeUploadMethods();
	
	foreach my $file (@files){
		$filePath = $pathaudits."/".$file;
		TraceInfo("Trying upload audit file: " . $filePath);
		
		# Intentamos con curl
		if ( -e $filePath && $curlAvailable ) {
			ExecAlternativeUploadMethod("curl",$filePath,$curlAvailable);
		}
		# Intentamos con wget
		if ( -e $filePath && $wgetAvailable ){
			ExecAlternativeUploadMethod("wget",$filePath,$wgetAvailable);
		}	
		# Intentamos con fusion-injector
		my $injectorPath = $workingdir."/perl/bin/".$injector;
		if ( -e $filePath && -e $injectorPath ){
			my $uploadOutput = undef;
			$uploadOutput = `$workingdir/perl/bin/perl $injectorPath $verboseInjector --no-ssl-check --file $filePath --url $urlinbox --remove`;
			TraceInfo($uploadOutput);				
			if ( -e $filePath ) {
				TraceInfo("Failed fusioninventory injector upload");
			}
			else{
				TraceInfo("Successfuly uploaded with fusioninventory injector.");
			}
		}
		# Intentamos con lynx
		if ( -e $filePath && $lynxAvailable ){
			ExecAlternativeUploadMethod("lynx",$filePath,$lynxAvailable);
		}
		# Si no pudimos subir el fichero, lo borramos.
		if (-e $filePath){
			TraceInfo("Failed upload audit file: " . $filePath);
		}
		else {
			TraceInfo("OK upload audit file: " . $filePath);
		}			
	}
}

# --------------------------------------------------------------------------------
# Get panix version
sub GetVersion {
	my @parameters = @_;
	for (my $i = 0; $i < @parameters; $i++)	{
		my ($key, $value) = split(/=/, $parameters[$i]);		
		if ($key =~ /-sv/i || $key =~ /--setVersion/i)	{
			return $value;
		}
	}
}

# --------------------------------------------------------------------------------
# Show plugin version
sub ShowVersion {
	
	print "Panix agent perl launcher for Unix and Linux " . $version . "\n";
	my $output = `$workingdir/$agent -v`;
	print $output;
}

# --------------------------------------------------------------------------------
# Show help 
sub ShowHelp {
	print "[USAGE]: $0 [-s=<url inbox>|--server=<url inbox>] [-l=<audit destination path>|--local=<audit destination path>] [-v=<level>|--verbose=<level>] [-V|--version] [-h|--help] [-i=<path_audits>|--in=<path_audits>] [-sv|--setVersion=<version>]\n";
	print "Where:\n";
	print "\t-s | --server is the url inbox where audit should be sended.\n";
	print "\t-l | --local is the local directory where audit should be stored.\n";
	print "\t-d | --directory is the working directory, " . $basedir . "/panix_temp by default..\n";
	print "\t-v | --verbose to indicate verbosity level; 0 -> Error, 1 -> Warning, 2 -> Debug, 3 -> Info.\n";
	print "\t-V | --version shows this script version.\n";
	print "\t-h | --help show this help.\n";
	print "\t-i | --in path to send all audits to inbox. Nedeed url inbox\n";
	print "\t-C | --no-compression to send audit uncompressed\n"; 
	print "\t-sv | --setVersion to set version of Panix\n"; 
}

# --------------------------------------------------------------------------------
# Print ERROR Trace
sub TraceError {
	my ($msg) = @_;
	if ($debug >= 0){
		PrintMessage("#ERROR: $msg\n");
	}
}

# --------------------------------------------------------------------------------
# Print WARNING Trace
sub TraceWarning {
	my ($msg) = @_;
	if ($debug >= 1){
		PrintMessage("#WARNING: $msg\n");
	}
}

# --------------------------------------------------------------------------------
# Print INFO Trace
sub TraceInfo {
	my ($msg) = @_;
	if ($debug >= 2){
		PrintMessage("#INFO: $msg\n");
	}
}

# --------------------------------------------------------------------------------
# Print DEBUG Trace
sub TraceDebug {
	my ($msg) = @_;
	if ($debug >= 3){
		PrintMessage("#DEBUG: $msg\n");
	}
}

# --------------------------------------------------------------------------------
# Print DEBUG Trace
sub TraceDebugArray {
	my ($arrayName, @array) = @_;
	for(my $i = 0; $i < @array; $i++) {
		TraceDebug("${arrayName}[$i] = $array[$i]");
	}
}

# --------------------------------------------------------------------------------
# Print DEBUG Trace
sub PrintMessage {
	my ($msg) = @_;
	print $msg;
}

# --------------------------------------------------------------------------------
# Escape XML reserved characters
sub EscapeXMLValue
{
	my ($xmlValue) = @_;
	$xmlValue =~ s/&(?!(quot|apos|lt|gt|amp);)/&amp;/g;
	$xmlValue =~ s/'(?!(quot|apos|lt|gt|amp);)/&apos;/g;
	return $xmlValue;
}
