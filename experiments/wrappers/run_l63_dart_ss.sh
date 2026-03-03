#!/bin/sh 

# -------------------------------------------------------------
# Henry Santer: February 2026
#
# Wrapper script for running components of DART
# -------------------------------------------------------------

# Helper function for making sure directory exists
function check_path
{
    fpath=${1}
    if [[ ! -d ${fpath} ]]; then
        echo "!!! Fail: directory ${fpath} does not exist !!!"
        exit 1
    fi
}

echo " ============================================"
echo "   Starting experiment ${exp}"

# Generate main run directory for components
mkdir -p ${runp}
check_path ${runp}
cd ${runp}

# Modify namelist
#    -e "s/forcing.*/forcing                                    = 8.5,/g" \
cp ${modp}/input.nml ./input.nml
# TODO: learn sed
# note: syntax can change depending on OS
# old from JP scripts, probably deprecated
sed -e "s/ens_size       .*/ens_size                           = ${NL_ENS_SIZE},/g" \
    -e "s/num_output_state_members.*/num_output_state_members  = ${NL_ENS_SIZE},/g" \
    -e "s/num_output_obs_members.*/num_output_obs_members      = ${NL_ENS_SIZE},/g" \
    -e "s/obs_estimation_flavor .*/obs_estimation_flavor=${NL_OBS_EST_FLAVOR},/g" \
    -e "s/obs_sequence_out_name .*/obs_sequence_out_name='obs_seq.final.${postf}',/g" \
    -e "s/obs_sequence_name .*/obs_sequence_name='obs_seq.final.${postf}',/g" \
    input.nml > input.nml.edit
mv input.nml.edit input.nml

# for experiments where no variance estimation is being used, we'll still
# end up computing them, but they'll never be used/seen
if [[ ${NL_OBS_EST_FLAVOR} == 4 ]]; then
    sed -e "s/use_variances       .*/use_variances                           = .false.,/g" \
	-e "s/obs_estimation_flavor .*/obs_estimation_flavor=1,/g" \
	input.nml > input.nml.edit
    mv input.nml.edit input.nml
fi



# Generate observations from truth simulation 
if ${run_initial}; then
    
   echo " ============================================"
   echo "   Setting up obs sequence file"

   rm -rf ${initp}
   mkdir -p ${initp}
   check_path ${initp}
   cd ${initp}

   mkdir obs_chunks


   cp ${runp}/input.nml ./
   echo "Copying ${modp}/obs_seq.out to ${initp} . . ."
   cp ${modp}/obs_seq.out .
   ln -sf ${datap}/chunk_group_obs.sh .
   ln -sf ${datap}/chunk_obs_seq.py .
   ln -sf ${modp}/obs_grouping_tool ./
   ln -sf ${modp}/subsets.in ./
   ln -sf ${datap}/obs_error_scripts/nongaussian_error.py ./


   # generate new obs sequences per experiment with different obs error distributions
   python nongaussian_error.py obs_seq.out ${EXP_FLAG}

   # assign obs group numbers in obs sequence
   ./chunk_group_obs.sh ${n_chunks} ${postf} > obs_chunking.log
   

   echo " ============================================"
   echo "   Grouping of obs and breaking up into chunks complete."
fi

# Run ensemble filter
if ${run_filter}; then

   echo " ============================================"
   echo "   Running cycling DA experiment"

   rm -rf ${filterp}
   mkdir -p ${filterp}
   check_path ${filterp}
   cd ${filterp}

   mkdir output_chunks

   cp ${runp}/input.nml ./
   cp -r ${initp}/obs_chunks ./
   ln -sf ${modp}/obs_diag ./
   ln -sf ${modp}/filter ./
   ln -sf ${modp}/filter_input_list.txt ./
   ln -sf ${modp}/filter_output_list.txt ./
   ln -sf ${modp}/perfect_input.nc ./
   cp ${modp}/filter_input.nc ./
   ln -sf ${modp}/obs_sequence_tool ./
   ln -sf ${modp}/subsets.in ./
   ln -sf ${scriptp}/save_rmses.py ./
   ln -sf ${datap}/join_obs_seqs.py ./
   ln -sf ${datap}/join_obs_seqs.sh ./
   ln -sf ${modp}/obs_grouping_tool ./

   # Run filter
   echo "Starting to filter!"
   # mpirun -np 3 ./filter >& output.log



   for (( i=1; i<=${n_chunks}; i++ )); do
       cp obs_chunks/obs_seq.out.${postf}.${i} obs_seq.out
       mpirun -np 3 ./filter >& output.log
       mv obs_seq.final.${postf} output_chunks/obs_seq.final.${postf}.${i}
       cp filter_output.nc filter_input.nc
   done

   ./join_obs_seqs.sh ${n_chunks} > obs_joining.log
   
fi



echo " ============================================"

if ${run_plotting}; then
    echo " Plotting for experiment ${postf} "
    cd ${filterp}
    python ${plotcp}/plot_rmse.py output_chunks/obs_seq.final.${postf}.joined "${rmse_label} RMSEs" ppo_rmses.png ${rmse_type}
    
    echo " Finished plotting for experiment ${postf} "
fi



echo " ============================================"
echo "   Experiment complete!"
echo " "
