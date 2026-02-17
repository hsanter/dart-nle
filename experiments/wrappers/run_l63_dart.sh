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
    -e "s/obs_sequence_in_name .*/obs_sequence_in_name='obs_seq.out.${postf}',/g" \
    -e "s/obs_sequence_out_name .*/obs_sequence_out_name='obs_seq.final.${postf}.${NL_OBS_EST_FLAVOR}',/g" \
    -e "s/obs_sequence_name .*/obs_sequence_name='obs_seq.final.${postf}.${NL_OBS_EST_FLAVOR}',/g" \
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


   cp ${runp}/input.nml ./
   echo "Copying ${modp}/obs_seq.out to ${initp} . . ."
   cp ${modp}/obs_seq.out obs_seq.out
   ln -sf ${modp}/obs_grouping_tool ./
   ln -sf ${modp}/subsets.in ./



   # assign obs group numbers in obs sequence
   ./obs_grouping_tool > output_grouping.log
   mv obs_seq.out.grouped obs_seq.out
   echo " ============================================"
   echo "   obs_grouping_tool complete"
   
   # generate new obs sequences per experiment with different obs error distributions
   ln -sf ${datap}/obs_error_scripts/nongaussian_error.py ./
   python nongaussian_error.py obs_seq.out ${EXP_FLAG}

fi

# Run ensemble filter
if ${run_filter}; then

   echo " ============================================"
   echo "   Running cycling DA experiment"

   rm -rf ${filterp}
   mkdir -p ${filterp}
   check_path ${filterp}
   cd ${filterp}

   cp ${runp}/input.nml ./
   cp ${initp}/obs_seq.out.${postf} ./
   ln -sf ${modp}/obs_diag ./
   ln -sf ${modp}/filter ./
   ln -sf ${modp}/filter_input_list.txt ./
   ln -sf ${modp}/filter_output_list.txt ./
   ln -sf ${modp}/perfect_input.nc ./
   ln -sf ${modp}/filter_input.nc ./
   ln -sf ${modp}/obs_sequence_tool ./
   ln -sf ${modp}/subsets.in ./
   ln -sf ${datap}/obs_error_scripts/seq_to_np_binary.py ./
   ln -sf ${datap}/obs_error_scripts/seq_to_np_binary_full_ensemble.py ./
   ln -sf ${datap}/obs_error_scripts/seq_to_np_binary_power.py ./
   ln -sf ${shellp}/save_rmses.py ./

   # Run filter
   echo "made it here!"
   mpirun -np 3 ./filter >& output.log

   echo " ============================================"
   echo "   Filter complete - running obs space diagnostics"
   # Run obs_diag
   ./obs_diag >& output_obs.log


   cp obs_diag_output.nc obs_diag_output_${NL_OBS_EST_FLAVOR}.nc

   if ${run_plotting}; then
       python ${plotcp}/plot_rmse.py obs_seq.final.${postf}.${NL_OBS_EST_FLAVOR} "Prior and Posterior RMSEs" ppo_rmses.png
   fi

   python save_rmses.py obs_diag_output_${NL_OBS_EST_FLAVOR}.nc rmse_${postf}_${NL_OBS_EST_FLAVOR}.npy ${postf}

fi


echo " ============================================"
echo "   Experiment complete!"
echo " "
