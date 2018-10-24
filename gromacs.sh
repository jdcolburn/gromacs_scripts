#!/bin/bash
# Script for handling MD in GROMACS - J.D. Colburn 31/01/18

#ALL OF THE MOLECULAR DYNAMICS STEPS
function molecular_dynamics {

#get name
intro
printf ' > Please choose one: '												#asks for name of peptide
read PDB																	#the name you type in is saved as the variable "$PDB"

initialise 

#set up directory
if [ -a $INITDIR/$PDB.pdb ]; then										    #checks that there is a ".pdb" with the same name in "peptides/geom/initial/"
	mkdir -p $SYSDIR														#if there is, then makes a directory for it in /peptides/
fi																			

#main loop
if [ -a $NPTDIR/$PDB\_npt.gro ]; then									    #checks that NPT step has been completed by checking that npt.gro exists
	dyn																		#if it has, call "dyn" function, else go to next command
else
	if [ -a $NVTDIR/$PDB\_nvt.gro ]; then								    #checks that NVT step has been completed by checking that nvt.gro exists
		npt																	#if it has, call "npt" function, else go to next command
	else
		if [ -a $EMDIR/$PDB\_em.gro ]; then									#checks that EM step has been completed by checking that em.gro exists
			nvt																#if it has, call "nvt" function, else go to next command
		else
			if [ -a $INITDIR/$PDB.pdb ]; then							    #checks that there is a ".pdb" with the same name in "peptides/geom/initial/"
				setup														#if there is, call "setup" function (the first step)
			else
				echo \ Could not find file \'$PDB.pdb\'						#else, there isn't a ".pdb" file in "peptides/geom/initial/"
			fi
		fi
	fi
fi

echo ''
}

#lists all peptides based on ".pdb" entries in "peptides/geom/initial/"
function intro {
echo '' && echo 'MOLECULAR DYNAMICS' && echo ''

printf 'Available structures: | '
cd $INITDIR && ls *.pdb | sed 's/....$//' > $INITDIR/molecules.txt              #makes "peptides.txt" which lists .pdb files in "peptides/geom/initial/"

MOLS="$(< $INITDIR/molecules.txt)"										        #declares variable "PROT" for each line in "peptides.txt"
for MOL in $MOLS; 
do
	printf $MOL && printf ' | '											    #prints each line in peptides.txt to the terminal"
done
echo '' && echo ''
}

#setup and minimisation
function setup {
mkdir -p $EMDIR && cd $EMDIR

cp $INITDIR/$PDB.pdb $EMDIR/$PDB.pdb

if [ -a $INITDIR/$PDB.pdb ]; then #make .gro:
echo " +-----------------+"
echo " | > PDB to GMX    |"
echo " +-----------------+"
$GROMDIR/pdb2gmx -f $EMDIR/$PDB.pdb -ignh -asp -glu -o $EMDIR/$PDB\_read.gro -p $EMDIR/topol.top -water tip3p
#$GROMDIR/pdb2gmx -f $EMDIR/$PDB.pdb -ignh -o $EMDIR/$PDB\_read.gro -p $EMDIR/topol.top -water tip3p
else
	exit
fi

if [ -a $EMDIR/$PDB\_read.gro ]; then #define box:
echo " +-----------------+"
echo " | > EditConf      |"
echo " +-----------------+"
$GROMDIR/editconf -f $EMDIR/$PDB\_read.gro -o $EMDIR/$PDB\_box.gro -c -d 1.0 -bt cubic
else
	exit
fi

if [ -a $EMDIR/$PDB\_box.gro ]; then #solvate:
echo " +-----------------+"
echo " | > GenBox        |"
echo " +-----------------+"
$GROMDIR/genbox -cp $EMDIR/$PDB\_box.gro -cs spc216.gro -o $EMDIR/$PDB\_solv.gro -p $EMDIR/topol.top
else
	exit
fi

if [ -a $EMDIR/$PDB\_solv.gro ]; then #ionise system:
echo " +-----------------+"
echo " | > Grompp        |"
echo " +-----------------+"
$GROMDIR/grompp -f $MDPDIR/ions.mdp -c $EMDIR/$PDB\_solv.gro -p $EMDIR/topol.top -o $EMDIR/ions.tpr
echo " +-----------------+"
echo " | > GenIon        |"
echo " +-----------------+"
$GROMDIR/genion -s $EMDIR/ions.tpr -o $EMDIR/$PDB\_ions.gro -p $EMDIR/topol.top -pname NA -nname CL -neutral
else
	exit
fi
  
if [ -a $EMDIR/$PDB\_ions.gro ]; then #energy minimisation:
echo " +-----------------+"
echo " | > Grompp        |"
echo " +-----------------+"
$GROMDIR/grompp -f $MDPDIR/minim.mdp -c $EMDIR/$PDB\_ions.gro -p $EMDIR/topol.top -o $EMDIR/$PDB\_em.tpr
echo " +-----------------+"
echo " | > MDrun minim   |"
echo " +-----------------+"
$GROMDIR/mdrun -v -deffnm $EMDIR/$PDB\_em
else
printf " Continue? (y/n): "
read ANS
if [ ${ANS} = 'y' ]; then
	echo " Continuing... "
	cp $EMDIR/$PDB\_solv.gro $EMDIR/$PDB\_ions.gro
	echo " +-----------------+"
	echo " | > Grompp        |"
	echo " +-----------------+"
	$GROMDIR/grompp -f $MDPDIR/minim.mdp -c $EMDIR/$PDB\_ions.gro -p $EMDIR/topol.top -o $EMDIR/$PDB\_em.tpr
	echo " +-----------------+"
	echo " | > MDrun minim   |"
	echo " +-----------------+"
	$GROMDIR/mdrun -v -deffnm $EMDIR/$PDB\_em
else
	exit
fi
fi

if [ -a $EMDIR/$PDB\_em.gro ]; then #make pdb for minimised:
echo " +-----------------+"
echo " | > EditConf      |"
echo " +-----------------+"
$GROMDIR/editconf -f $EMDIR/$PDB\_em.gro -o $SYSDIR/$PDB\_pre-dyn.pdb
else
	exit
fi

cd $MAINDIR
}

#NVT equilibration
function nvt {
echo ''
echo ' > Setting up NVT...'
mkdir -p $NVTDIR && cd $NVTDIR
cp $EMDIR/*.itp 	$NVTDIR/
cp $EMDIR/topol.top $NVTDIR/topol.top

$GROMDIR/grompp -f $MDPDIR/nvt.mdp -c $EMDIR/$PDB\_em.gro -p $NVTDIR/topol.top -o $NVTDIR/$PDB\_nvt.tpr

echo '#!/bin/sh'              > sub-gromacs_nvt
echo '#$ -cwd'               >> sub-gromacs_nvt
echo '#$ -pe mpich 8'        >> sub-gromacs_nvt
echo ' '                     >> sub-gromacs_nvt

echo $GROMDIR/mdrun -deffnm $NVTDIR/$PDB\_nvt >> $NVTDIR/sub-gromacs_nvt

qsub -N nvt_$PDB $NVTDIR/sub-gromacs_nvt
cd $MAINDIR
}

#NPT equilibration
function npt {
echo ''
echo ' > Setting up NPT...'
mkdir -p $NPTDIR && cd $NPTDIR
cp $NVTDIR/*.itp 	 $NPTDIR/
cp $NVTDIR/topol.top $NPTDIR/topol.top

$GROMDIR/grompp -f $MDPDIR/npt.mdp -c $NVTDIR/$PDB\_nvt.gro -p $NPTDIR/topol.top -t $NVTDIR/$PDB\_nvt.cpt -o $NPTDIR/$PDB\_npt.tpr

echo '#!/bin/sh'              > sub-gromacs_npt
echo '#$ -cwd'               >> sub-gromacs_npt
echo '#$ -pe mpich 8'        >> sub-gromacs_npt
echo ' '                     >> sub-gromacs_npt

echo $GROMDIR/mdrun -deffnm $NPTDIR/$PDB\_npt >> $NPTDIR/sub-gromacs_npt

qsub -N npt_$PDB $NPTDIR/sub-gromacs_npt
cd $MAINDIR
}

#production MD
function dyn {
echo ''
echo ' > Setting up production MD...'
mkdir -p $MDDIR && cd $MDDIR
cp $NPTDIR/*.itp 	 $MDDIR/
cp $NPTDIR/topol.top $MDDIR/topol.top

$GROMDIR/grompp -f $MDPDIR/md.mdp -c $NPTDIR/$PDB\_npt.gro -t $NPTDIR/$PDB\_npt.cpt -p $MDDIR/topol.top -o $MDDIR/$PDB\_md.tpr

echo '#!/bin/sh'              > sub-gromacs_md
echo '#$ -cwd'               >> sub-gromacs_md
echo '#$ -pe mpich 8'        >> sub-gromacs_md
echo ' '                     >> sub-gromacs_md

echo $GROMDIR/mdrun -deffnm $MDDIR/$PDB\_md >> $MDDIR/sub-gromacs_md

qsub -N md_$PDB $MDDIR/sub-gromacs_md
cd $MAINDIR
}

#PRE QM OPTIMISATION OF SNAPSHOTS
function snapshot_optimisation {
echo '' && echo "PRE-QM OPTIMISATION" && echo ''

printf " > Enter system of interest: "
read PDB

initialise

if [ -d $MDDIR ]; then	
	echo "   Found directory: $MDDIR"
	echo ''
else
	echo "   No MD found for peptide: '$PDB'" && echo ''
	exit
fi

re='^[0-9]+$' #check answer is a number
printf ' > Enter time (ps) of interest (1-1000): '
read SNAP
if ! [[ ${SNAP} =~ ${re} ]] ; then
	echo " '$SNAP' is not a valid frame." >&2
else
	opt
fi
}

#minimises chosen snapshot for chosen peptide
function opt {
OPTDIR="$SYSDIR/$SNAP/opt"

mkdir -p $OPTDIR
cd $OPTDIR

START=$SNAP
END=$((SNAP+1))

$GROMDIR/trjconv -f $MDDIR/$PDB\_md.trr -s $MDDIR/$PDB\_md.tpr -pbc mol -o $OPTDIR/$SNAP.gro -b $START -e $START	<<< 0

#sed -i 's/CL /CLA/'   $OPTDIR/$SNAP.pdb
#sed -i 's/ CL /CLA /' $OPTDIR/$SNAP.pdb

#$GROMDIR/pdb2gmx -f $OPTDIR/$SNAP.pdb -ignh -ter -o $OPTDIR/$SNAP.gro -water tip3p

cp $MDDIR/topol.top $OPTDIR/topol.top

if [ -a $OPTDIR/$SNAP.gro ]; then
$GROMDIR/grompp -f $MDPDIR/optim.mdp -c $OPTDIR/$SNAP.gro -p $OPTDIR/topol.top -o $OPTDIR/$SNAP\_opt.tpr
else
	exit
fi

if [ -a $SNAP\_opt.tpr ]; then
$GROMDIR/mdrun -v -deffnm $OPTDIR/$SNAP\_opt
else
	exit
fi

#$GROMDIR/editconf -f $OPTDIR/$SNAP\_opt.gro -pbc -o $OPTDIR/$SNAP\_opt.pdb

# generates a useable pdb for the snapshot
$GROMDIR/trjconv -f $OPTDIR/$SNAP\_opt.trr -s $OPTDIR/$SNAP\_opt.tpr -pbc mol -o $OPTDIR/$SNAP\_opt.pdb <<< 0

cd $MAINDIR
}

function ligands {

sleep 0
}

function get_snapshots {
echo '' && echo "GET SNAPSHOTS FROM TRAJECTORY" && echo ''

printf " > Enter system of interest: "
read PDB

initialise

printf "   First frame: "
read FIRST
printf "    Last frame: "
read LAST
printf "     Step size: "
read STEP
echo ''

SNAPDIR="$SYSDIR/snaps"
mkdir -p $SNAPDIR

SNAPS="$(seq $FIRST $STEP $LAST)"
for SNAP in $SNAPS; 
do
	START=$SNAP
	END=$SNAP
	$GROMDIR/trjconv -f $MDDIR/$PDB\_md.trr -s $MDDIR/$PDB\_md.tpr -pbc mol -o $SNAPDIR/$PDB\_$SNAP.pdb -b $START -e $END	<<< 0								 
done

cd $MAINDIR
}

function pre_initialise {
GROMDIR="/cvos/shared/apps/gromacs/bin"
MAINDIR="/home/jdc6/perox_gromacs"
INITDIR="$MAINDIR/geom/initial"
 MDPDIR="$MAINDIR/mdp"
 }
 
function initialise {
 SYSDIR="$MAINDIR/$PDB"
  EMDIR="$SYSDIR/em"
 NVTDIR="$SYSDIR/nvt"
 NPTDIR="$SYSDIR/npt"
  MDDIR="$SYSDIR/md"
}

pre_initialise

echo $MAINDIR
echo $INITDIR
echo $MDPDIR

echo ''
echo "What would you like to do?"
echo " 1. Molecular Dynamics"
echo " 2. Pre-QM Optimisation"
echo " 3. Snapshots from MD"
echo ''
printf " > Please choose an option (1 or 2): "
read ANS
if [ ${ANS} = '1' ]; then
	molecular_dynamics
elif [ ${ANS} = '2' ]; then
	snapshot_optimisation
elif [ ${ANS} = '3' ]; then
	get_snapshots
else
	echo " That is not a valid option."
fi
