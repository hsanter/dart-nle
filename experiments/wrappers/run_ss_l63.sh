#!/bin/sh


# -------------------------------------------------------------
# Henry Santer: February 2026
#
# Main script for running cycling data assimilation experiments
# with DART, using a range of parameters
# -------------------------------------------------------------


function check_path
{
    fpath=${1}
    if [[ ! -d ${fpath} ]]; then
        echo "!!! Fail: directory ${fpath} does not exist !!!"
        exit 1
    fi
}


# --- Specify run options ---
export run_filter=true      # Run ensemble filter
export run_plotting=false      # Run plotting routines
export rmse_type=4

if [[ $rmse_type == 1 ]]; then
    export rmse_label='OMB'
elif [[ $rmse_type == 2 ]]; then
    export rmse_label='OMA'
elif [[ $rmse_type == 3 ]]; then
    export rmse_label='TMB'
elif [[ $rmse_type == 4 ]]; then
    export rmse_label='TMA'
fi

# --- How to divy up obs sequence files ---
# CHANGE THESE THREE VARIABLES TOGETHER
export n_chunks=400
export chunk_len_days=0
export chunk_len_secs=3600


# --- KECD Options ---

# 1: no estimation
# 2: likelihood estimation 
export kecd_estimation=2
export train_on_truth=true
export bw=0.02
export knnf=0.1
export n_train=400
export compute_pyx_every=50


# -- Model Options --

# 1: L63
# 2: L96
# 3: L04?
export m_flag=2

if [[ $m_flag == 1 ]]; then
    export model='63'
elif [[ $m_flag == 2 ]]; then
    export model='96'
elif [[ $m_flag == 3 ]]; then
    export model='04'
fi

export exp="L${model} Experiment"

echo " "
echo "-------------------------------------------------"
echo " Setting up experiments with constant parameters:" 
echo "    Experiment name  = ${exp}"
echo " Ensure that observing network is properly defined!"
echo "-------------------------------------------------"
echo " "

# Paths to data and DART components
export dartp=/Users/santer/dart-nle
export modp=${dartp}/models/lorenz_${model}/work
export datap=${dartp}/experiments/setup
export shellp=${dartp}/experiments/wrappers
export scriptp=${dartp}/experiments/scripts
export plotcp=${dartp}/experiments/plotting


# Ranges of parameter values to explore
#    ens_range            <-- ensemble size
#    infl_range           <-- mixing coefficient (PF)
#    cutoff_range         <-- localization length scale
#    NL_FRAC_NEFF         <-- ensemble size fraction used for regularization (PF)

ens_range=( 80 )
obs_est_flavor_range=( 0 )
# 0: unchanged obs errors
# 1: perfect observations
# 2: logistic error (i.e. symmetric, but with heavier tails than a gaussian)
# 3: state dependent gaussian error
# 4: lognormal
# 5: higher variance gaussian
# 6: lower variance gaussian
# 7: biased gaussian
# 8: bias-corrected lognormal
experiment_range=( 3 )


for ens in ${ens_range[@]}; do
    for exp_f in ${experiment_range[@]}; do
        # Set experiment parameters
        export NL_ENS_SIZE=$ens
	export EXP_FLAG=$exp_f

	
	# for bookkeeping: string manipulation so that
	# parameters are nicely present in file names
	
	if [[ $exp_f == 0 ]]; then
	    export postf='control'
	    export true_var=2
	elif [[ $exp_f == 3 ]]; then
	    export postf='state_dep_gaussians'
	elif [[ $exp_f == 5 ]]; then
	    export postf='gaussian_high'
	    export true_var=4
	elif [[ $exp_f == 6 ]]; then
	    export postf='gaussian_low'
	    export true_var=0.75
	elif [[ $exp_f == 7 ]]; then
	    export postf='biased_gaussian'
	    export true_var=4
	fi
	
	    
        # Setup temporary run directory for each experiment
        export runp=${dartp}/experiments/output/l${model}/run_${postf}
        export initp=${runp}/initial

	# before each experiment, generate obs file with prescribed obs error
	export run_initial=false     # Generate obs from a truth simulation
	
	export OUTPUT_DIR_NAME=run_${postf}
	echo $OUTPUT_DIR_NAME

	for flav in ${obs_est_flavor_range[@]}; do
	    
	    export NL_OBS_EST_FLAVOR=${flav}
		
	    estring="${exp} with Ne = ${ens}, obs error experiment ${exp_f}, method ${flav}"
	    export filterp=${runp}/filter${flav}
	    
	    # Run DART script if output doesn't exist
	    if [[ 1 == 1 ]]; then
		echo " "
		echo "--------------------------------"
		echo " Running $estring"
		echo "--------------------------------"
		echo " "
		./run_l63_dart_ss.sh
	    else
		echo " Skipping $estring"
	    fi
	    
	    export run_initial=false     # once we've done it once per experiment
	    # we don't want to do it again.
	    
	    

		
	done
    done	# param for
done

exit
