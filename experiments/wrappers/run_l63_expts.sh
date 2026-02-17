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
export run_plotting=true      # Run plotting routines

# Specifiy Case1
export case=1 # Linear measurement operator
#export case=2 # Nonlinear measurement operator (squared variables)

export exp=
#  export NL_INF_FLAVOR=0
# export NL_INF_FLAVOR=3  # fixed SS inflation
export NL_OUT_THRES=-1 # no QC checking of outliers

echo " "
echo "-------------------------------------------------"
echo " Setting up experiments with constant parameters:" 
echo "    Experiment name  = ${exp}"
echo " Ensure that observing network specified in"
echo " obsgen/seq_files/obs_seq_..._.in is desired"
echo "-------------------------------------------------"
echo " "

# Paths to data and DART components
export dartp=/Users/santer/dart-nle
export modp=${dartp}/models/lorenz_63/work
export datap=${dartp}/experiments/setup
export shellp=${dartp}/experiments/wrappers
export plotcp=${dartp}/experiments/plotting


# Ranges of parameter values to explore
#    ens_range            <-- ensemble size
#    infl_range           <-- mixing coefficient (PF)
#    cutoff_range         <-- localization length scale
#    NL_FRAC_NEFF         <-- ensemble size fraction used for regularization (PF)

ens_range=( 10 )
obs_est_flavor_range=( 1 )
# 0: unchanged obs errors
# 1: perfect observations
# 2: logistic error (i.e. symmetric, but with heavier tails than a gaussian)
# 3: state dependent gaussian error
# 4: lognormal
# 5: higher variance gaussian
# 6: lower variance gaussian
# 7: biased gaussian
# 8: bias-corrected lognormal
experiment_range=( 5 )


for ens in ${ens_range[@]}; do
    for exp_f in ${experiment_range[@]}; do
        # Set experiment parameters
        export NL_ENS_SIZE=$ens
	export EXP_FLAG=$exp_f

	
	# for bookkeeping: string manipulation so that
	# parameters are nicely present in file names
	
        a=${ens}
        b=${exp_f}
	
        if [[ ${#a} -eq 2 ]]; then
	    a=0${a}
        elif [[ ${#a} -eq 1 ]]; then
	    a=00${a}
        fi
	
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
        export runp=${dartp}/experiments/output/run_${postf}
        export initp=${runp}/initial

	# before each experiment, generate obs file with prescribed obs error
	export run_initial=true     # Generate obs from a truth simulation

	
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
		./run_l63_dart.sh
	    else
		echo " Skipping $estring"
	    fi
	    
	    export run_initial=false     # once we've done it once per experiment
	    # we don't want to do it again.
	    
	    

		
	done
	
	    # start plotting
	    
	    
	if ${run_plotting}; then
	    export plotp=/Users/santer/dart-nle/plotting/figs/$OUTPUT_DIR_NAME
	    rm -rf ${plotp}
	    mkdir -p ${plotp}
	    check_path ${plotp}

	    cp plot_evolution.py plot_evolution_base.py
	    sed -e "s/exp_leaf = ''.*/exp_leaf = '${postf}'/g" \
		-e "s/exp_name =.*/exp_name = '${OUTPUT_DIR_NAME}\/filter'/g" \
		plot_evolution.py > plot_evolution.py.edit
	    mv plot_evolution.py.edit plot_evolution.py

	    
	    echo $estring >> plotting_stats.out
	    python plot_evolution.py >> plotting_stats.out

	    mv plot_evolution_base.py plot_evolution.py
	    
	    
	    echo "Finished plotting for experiment ${exp_f}"
	fi
    done	# param for
done

exit
