#!/bin/bash

# plugin creado por Daniel Dueñas
# Plugin para chequeo de datamovers en celerra a través de nrpe

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
VERSION="Version 1.0,"
AUTHOR="2015, Daniel Dueñas Domingo (mail:dduenasd@gmail.com)"

print_version() {
    echo "$VERSION $AUTHOR"
}

print_use(){
   echo Use:
   echo "./$PROGNAME -n <name1,name2,...> [-id <identificador>]"
}
print_error(){
   print_use
   echo ""
   echo "escribe './$PROGNAME -h' para ver la ayuda"
   exit $ST_UK
   }

print_help(){
    print_version $PROGNAME $VERSION
    echo ""
    echo "Description:"
    echo "$PROGNAME es un plugin de Nagios para chequeo de datamovers en celerra a través de nrpe"
    echo ""
	print_use
	echo "Example:"
	echo "./$PROGNAME "
	echo ""
	echo "OPTIONS:"
	echo "-h|--help)"
	echo "   Show this help"
	echo "-v, --verbosity"
	echo "   verbosity mode"
	echo "-n|--name)"
	echo "   names of datamovers checked."
    echo "   If there are several they must be separated by commas."
    echo "   e.g.: -n vdm_1,vdm_2,server_1"
	
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
verbosity=0
encontrado=0
dmlist=""

   
datamover_list(){
   #number of dm (summarize the number of text lines which begin by “id”) 
   number_dm=`echo "$1" | sed -n '/^id/p' | wc -l`
   #number of vdm (summarize the number of text lines which begin by “id”)
   number_vdm=`echo "$2" | sed -n '/^id/p' | wc -l`
   cont=1
   until test $cont -gt $number_dm ; do
	  page=''$cont'p'
      dm_name[$cont]=`echo "$1"  | sed -n '/^name/p' | sed -n $page | cut -d= -f2 | cut -d " " -f2`
	  dm_defined[$cont]=`echo "$2"  | sed -n '/defined =/p' | sed -n $page | cut -d= -f2 | cut -d " " -f2`
	  dm_actual[$cont]=`echo "$2"  | sed -n '/actual =/p' | sed -n $page | cut -d= -f2`
	  dmlist="$dmlist, ${dm_name[$cont]}" 
	  cont=`expr $cont + 1`
   done
   
   cont=1
   until test $cont -gt $number_vdm ; do
	  page=''$cont'p'
      vdm_name[$cont]=`echo "$2"  | sed -n '/^name/p' | sed -n $page | cut -d= -f2 | cut -d " " -f2`
	  vdm_defined[$cont]=`echo "$2"  | sed -n '/defined =/p' | sed -n $page | cut -d= -f2 | cut -d " " -f2`
	  vdm_actual[$cont]=`echo "$2"  | sed -n '/actual =/p' | sed -n $page | cut -d= -f2`	  
	  dmlist="$dmlist, ${vdm_name[$cont]}"
	  cont=`expr $cont + 1`
   done
   
   if (test $verbosity -gt 0) then 
      echo -e "datamover list: $dmlist"
   fi
}

test_datamover(){
if (test "$2" = "enabled") then
	if (test "$3" = " loaded, active") then
			temp_state=$ST_OK
		else
		    temp_state=$ST_CR
		    output="vdm $1 isn't loaded and active, is $3"
		fi
		else
		    temp_state=$ST_CR
		    output="vdm $1 isn't enabled, is $2"
fi
output="vdm $1 is $3"
}

datamover_find_name(){
   #find in data movers
   cont=1
   until test $cont -gt $number_dm ; do
      if (test "${dm_name[$cont]}" = "$1") then
         encontrado=1
		 test_datamover "${dm_name[$cont]}" "${dm_defined[$cont]}" "${dm_actual[$cont]}"
		 break
      fi
	  cont=`expr $cont + 1`
   done
   
   cont=1
   until test $cont -gt $number_vdm ; do
      if (test "${vdm_name[$cont]}" = "$1") then
         encontrado=1
		 test_datamover "${vdm_name[$cont]}" "${vdm_defined[$cont]}" "${vdm_actual[$cont]}"
		 break
      fi
	  cont=`expr $cont + 1`
   done
}

read_datamover_names(){
	#read names of dm and vdm
	names_comma=$1","
	cont=1
	while true ; do
		fnum="f"$cont
		temp=`echo $names_comma|cut -d, -"$fnum"`
		if (test "$temp" = "") then
			break
		else
			name[$cont]="$temp"
			cont=`expr $cont + 1`
		fi
	done
}
#no parameters
if test $# -eq 0
	then print_error
fi

while test -n "$1"; do
   case "$1" in
    
		--help|-h) 
			print_help
			;;
		--name|-n)
			names=$2
			shift
			;;
		--verbosity|-v)
		    verbosity=1
			shift
			;;				
    esac
	shift
done

#read names parameter
read_datamover_names $names

#info of all datamovers
dm_text=`nas_server -info -all`
#info of all virtual datamovers
vdm_text=`nas_server -info -vdm -all`

datamover_list "$dm_text" "$vdm_text"
state=$ST_OK
for i in "${name[@]}"
do 
	encontrado=0
	datamover_find_name $i
	if test $encontrado -eq 0
		then
		state=$ST_UK
		output="data mover $i not found"
		output_long="valid dm and vdm names: $dmlist"
		break
	fi
	if test $temp_state -gt $state 
		then
		state=$temp_state
	fi
done



#state string set
if test $state -eq $ST_OK
	then statestring="OK"
	output="data movers $names are ok"
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
