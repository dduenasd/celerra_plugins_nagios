#!/bin/bash

# plugin creado por Daniel Dueñas
# Plugin para chequeo de cuotas en celerra a través de nrpe

# Este plugin debe copiarse en la máquina celerra dentro del directorio donde están los scripts a los que se hace
# referencia en el fichero de configuración de nrpe dentro de la configuración de nagios en la máquina celerra.

# plugin developed by Daniel Dueñas

#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

PROGNAME=`basename $0`
VERSION="Version 1.1,"
AUTHOR="2013, Daniel Dueñas Domingo (mail:dduenasd@gmail.com)"

print_version() {
    echo "$VERSION $AUTHOR"
}

print_use(){
   echo Uso:
   echo "./$PROGNAME -f <file_system> [-id <identificador>] [-ff] [-w <warning>] [-c <critical>]"
   echo ""
   echo "escribe './$PROGNAME -h' para ver la ayuda"
   exit $ST_UK
}

print_help(){
    print_version $PROGNAME $VERSION
    echo ""
    echo "Description:"
    echo "$PROGNAME es un plugin de Nagios para chequeo de cuotas en celerra a través de nrpe"
	echo "Con performance data"
    echo ""
    echo "Uso:"
    echo "./$PROGNAME -f <file_system> [-id <identificador>] [-ff] [-w <warning>] [-c <critical>]"
    echo ""
	echo "Example:"
	echo "./$PROGNAME -f my_file_system -c 96 -id 2"
	echo ""
	echo "OPTIONS:"
	echo "-h|--help)"
	echo "   Muestra esta ayuda"
    echo "-f|--fs)"
	echo "   Nombre del file system"
	echo "-w|--warning)"
	echo "   Es el valor en el cual nagios alarma como warning, se expresa en porcentaje ocupado ej:80, este parámetro es opcional"
	echo "   en caso de no indicarse(lo mas común), se tomará como valor de warning el valor soft que muestra celerra"
	echo "-c|--critical)"
	echo "   Es el valor en el cual nagios alarma como crítico, se expresa en porcentaje ocupado ej:95"
	echo "-ff|--files)"
	echo "   elegir esta opción sin parámetros si tenemos fijadas cuotas en número de archivos"
	echo "-id|--identificador)"
	echo "   indica el identificador del directorio que se quiere monitorizar la cuota, si no existe este parámetro, se monitorizarán"
	echo "   todos los directorios de ese file system en el mismo servicio, para ver los identificadores, hay que ejecutar en la máquina celerra:"
	echo "   nas_quotas -list -tree -fs fs_bomberos"
	echo ""
	
    exit $ST_UK
}

ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3


#defino variables
state=$ST_UK
output=""
output_long=""
perfdata=""
files_cuotas="no"
unidad="KB"
existe_warning=0
existe_critical=0
es_warning=0
es_critico=0
num_critico=0
num_warning=0

#funciones

#comprueba si el dato es un número entero
checkInteger(){
   if [[ $1 = *[[:digit:]]* ]]; then
      a=0 #numerico
   else
      a=1 #no numerico
   fi
   return $a
}

#Analiza el valor de critical
analizaCritical(){
   checkInteger $critical
   if (test $? -eq 0) then
      if ( test $critical -gt 100 ) then
         echo "El valor de critical debe estar entre 0 y 100"
		 exit $ST_UK
	  fi
   else
      echo "El valor de critical no es numerico"
	  exit $ST_UK
   fi
}    

#Convierte datos de K en MB o en GB
convierteKb(){
   checkInteger $1
   if (test $? -eq 0) then
      KB=$1
      if (test $KB -gt 1) then
         valor=$KB
	     unidad="KB"
      fi
      MB=`expr $KB / 1024`
      if (test $MB -gt 1) then
         valor=$MB
	     unidad="MB"
      fi
      GB=`expr $MB / 1024`
      if (test $GB -gt 1) then
         valor=$GB
	     unidad="GB"
      fi
      conversion="$valor$unidad"
   else
      conversion=$1
   fi
}

#calcula porcentaje y devuelve los límites para el perfdata
calcula_datos(){
   checkInteger $1
   if (test $? -eq 0) then
      perf_usado=`expr $1 \* 1024`
      convierteKb $1
	  us=$conversion
      checkInteger $2
	  #todos los datos son numericos
	  if (test $? -eq 0) then
	     convierteKb $2
	     ha=$conversion
		 convierteKb $3
		 so=$conversion
         temp=`expr $1 \* 100`
         porcentaje_ocupacion=`expr $temp / $2`
		 perf_max=`expr $2 \* 1024`
		 #comprueba si se da el parámetro warning, sino tomará como warning el dato soft
		 if (test $existe_warning -eq 1) then 
		    temp=`expr $2 \* $warning`
            temp=`expr $temp / 100`
			perf_warn=`expr $temp \* 1024`
			#comprueba si warning
			if (test $porcentaje_ocupacion -gt $warning) then 
			   es_warning=1 
			fi
		 else 
		    perf_warn=`expr $3 \* 1024`
			#comprueba si warning con dato soft
		    if(test $1 -gt $3) then 
		       es_warning=1 
			fi
		 fi
		 #comprueba si se da el parámetro warning
		 if (test $existe_critical -eq 1) then 
		    temp=`expr $2 \* $critical`
            temp=`expr $temp / 100`
			perf_crit=`expr $temp \* 1024`
			#comprueba si critico
			if (test $porcentaje_ocupacion -gt $critical) then 
			   es_critico=1 
			fi
         fi
      else
	     if (test $2 = "NoLimit") then
		    porcentaje_ocupacion="NoLimit"
		 else 
		    porcentaje_ocupacion="NoData"
	     fi
		 perf_max=""
		 perf_warn=""
		 perf_crit=""
	  fi
   else
      porcentaje_ocupacion="NoData"
	  perf_usado=""
	  perf_max=""
	  perf_warn=""
	  perf_crit=""	  
   fi 
}

#lista todos los directorios con cuota y extra los datos necesarios para tratar
lista_tree(){
   cont=1
   num="nonulo"
   text=`nas_quotas -list -tree -fs $1`
   cuotas=`nas_quotas -report -tree -fs $1`
    until test "$num" = ""; do
	  #Extrae el id del directorio con cuota
      num=`echo "$text"  | sed -n "$cont"p | cut -d '|' -f 2`
	  #comprueba si es dato numérico
	  checkInteger $num
	  if (test $? -eq 0) then
	     
		 id[$num]=$num
		 #extrae sólo el nombre del directorio
		 directorio[$num]=`echo "$text"  | sed -n "$cont"p | cut -d '|' -f 3 | cut -d '(' -f 1 | cut -d '/' -f 3-`
		 
		 #los parametros hay que cogerlos cada 10 espacios entre | y |
		 #el primero está en la posición 17, el segundo en la 18, etc, en la siguiente fila, hay que sumar 10 posiciones, 27,28,etc.
		 multiplicador=`expr $num - 1`
		 multiplicador=`expr $multiplicador \* 10`
		 pos=`expr 17 + $multiplicador` #posición para usado
 	     usado[$num]=`echo $cuotas | cut -d '|' -f "$pos"`
		 pos=`expr $pos + 1` #siguiente posición para soft
		 soft[$num]=`echo $cuotas | cut -d '|' -f "$pos"`
		 pos=`expr $pos + 1` #siguiente posición para hard
		 hard[$num]=`echo $cuotas | cut -d '|' -f "$pos"`
		 pos=`expr $pos + 1` #siguiente posición para time_left
		 time_left[$num]=`echo $cuotas | cut -d '|' -f "$pos"`
		 pos=`expr $pos + 1` #siguiente posición para files_used
		 files_used[$num]=`echo $cuotas | cut -d '|' -f "$pos"`
		 #si queremos datos de archivos
		 if (test "$2" = "si") then
			pos=`expr $pos + 1` #siguiente posición para files_soft
		    files_soft[$num]=`echo $cuotas | cut -d '|' -f "$pos"`
			pos=`expr $pos + 1` #siguiente posición para files_hard
			files_hard[$num]=`echo $cuotas | cut -d '|' -f "$pos"`
			pos=`expr $pos + 1` #siguiente posición para files_time_left
			files_time_left[$num]=`echo $cuotas | cut -d '|' -f "$pos"`
		 fi
	  fi
   cont=`expr $cont + 1`
   done
}

todos_id(){   
   num_directorios=${#id[*]}
   if (test $num_directorios -eq 0) then #comprueba que haya datos
      output="no hay ningún directorio con cuotas en ese filesystem o no existe el filesystem"
   fi
   for ax in ${!id[*]};
   do
      es_warning=0
	  es_critico=0
      state=$ST_OK
	  calcula_datos ${usado[$ax]} ${hard[$ax]} ${soft[$ax]}
	  if (test $es_warning -eq 1) then
	     if (test $es_critico -eq 1) then
		    num_critico=`expr $num_critico + 1`
			output_crit=$output_crit" crit: "${directorio[$ax]}"("$porcentaje_ocupacion"%)  "
		 else
		    num_warning=`expr $num_warning + 1`
			output_warn=$output_warn" warn: "${directorio[$ax]}"("$porcentaje_ocupacion"%)  "
		 fi
	  fi
	  #devuelve el valor del porcentaje de ocupación en la variable 'porcentaje_ocupacion'
      output_long="$output_long \n"${id[$ax]}":${directorio[$ax]} -- used:$us("$porcentaje_ocupacion"%) soft:$so hard:$ha ${time_left[$ax]} / num fi:${files_used[$ax]};"
	  perfdata=$perfdata"'${id[$ax]}:${directorio[$ax]}'="$perf_usado"B;$perf_warn;$perf_crit;0;$perf_max "
   done
   num_ok=`expr $num_directorios - $num_warning`
   num_ok=`expr $num_ok - $num_critico`
   if (test $num_warning -ne 0) then
      state=$ST_WR
	  output_tmp=$num_warning" warn, " 
   fi 
   if (test $num_critico -ne 0) then
      state=$ST_CR
      output_tmp=$num_critico" crit, "$output_tmp
   fi
   output=$num_directorios" directorios, "$output_tmp$num_ok" ok; "$output_crit$output_warn   
}

un_id(){
   if (test ${#id[*]} -eq 0) then #comprueba que haya datos
      output="no hay ningún directorio con cuotas en ese filesystem o no existe el filesystem"
   fi
   if (test ${id[$1]} -eq $1) then
      state=$ST_OK
      calcula_datos ${usado[$1]} ${hard[$1]} ${soft[$1]}
      output="${id[$1]} ${directorio[$1]} used:$us("$porcentaje_ocupacion"%) soft:$so hard:$ha ${time_left[$1]} ficheros:${files_used[$1]}"
	  perfdata="'${id[$1]}:${directorio[$1]}'="$perf_usado"B;$perf_warn;$perf_crit;0;$perf_max "
   else
      output="No existe ese identificador en ese filesystem o no existe el filesystem"
	  state=$ST_UK
   fi
   
   if (test $es_warning -eq 1) then
      state=$ST_WR
   fi
   
   if (test $es_critico -eq 1) then
      state=$ST_CR
   fi
}

#si no se ponen parámetros
if test $# -eq 0
	then print_use
fi

while test -n "$1"; do
   case "$1" in
    
		--help|-h) 
			print_help
			;;
		--fs|-f)
			fs=$2
			shift
			;;
		--warning|-w)
			warning=$2
			existe_warning=1
			shift
			;;
		--critical|-c)
			critical=$2
			checkInteger $critical
			existe_critical=1
			analizaCritical
			shift
			;;
		--identificador|-id)
		   identificador=$2
		   shift
		   ;;
		--files|-ff)
		   files_cuotas="si";
		   shift
		   ;;
				
    esac
	shift
done

#Selección de parámetros
#case $parameter in
#   p1)
#		;;
#   *)
#		echo Unknown option:$1
#		print_help
#        ;;
#esac

lista_tree $fs $files_cuotas
checkInteger $identificador
if (test $? -eq 0) then
   un_id $identificador
else 
   todos_id
fi

#state string set
if test $state -eq $ST_OK
	then statestring="OK"
elif test $state -eq $ST_WR
	then statestring="WARNING"
elif test $state -eq $ST_CR
	then statestring="CRITICAL"
elif test $state -eq $ST_UK
	then statestring="UNKNOWN"
fi
output=$(echo $output) #para quitar los espacios en blanco 
perfdata=$(echo $perfdata)
echo "$statestring - $output|$perfdata $output_long"
exit $state
