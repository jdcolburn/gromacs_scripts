# GROMACS Scripts

These are shell scripts for setting up classical MD simulations in GROMACS. 

They are designed to automate as much of the procedure as possible, and rely on a very specific directory structure being in place as well as a particular bash profile configuration. Chances are they won't work for you - let alone anyone not operating on the University of St Andrews HPC clusters. 

In any case they make my life significantly easier.

# gromacs.sh
Main script, will perform all simulation steps (two equilibration steps and and production run) for any suitable PDB input file, which must be provided by the user in ../geom/initial

# gromacs_ligand.sh 
Hastily cobbled together version of the above that is able to do the same but with one ligand. The user must provide a ligand.gro and ligand.itp file in ../geom/ligand. I recommend antechamber for this.

At a later date I will merge this with the main script and add some checks for erroneous inputs, etc. - as well as clearer user instructions. 
