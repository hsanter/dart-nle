# HMS
# given output files from obs_diag after coming from a number of experiments,
# plot the obs space RMSEs for each experiment against each other, and
# generate rank histograms for each experiment, and
# plot the evolution of the estimate of the observational error variance with time.
# does the above for both assimilated and unassimilated variables, as appropriate

import numpy as np
import matplotlib.pyplot as plt

# path = sys.argv[1]
# val = sys.argv[2]
# var = sys.argv[2]
exp_leaf = ''
exp_name = ''

model=''

out_plot_leaf = ''

num_not_found = 0

found_big = False
found_bigs = False
found_kar = False
found_cnt = False
found_drz = False

try:
    print('/Users/santer/dart-nle/experiments/output/' +
                       exp_name + '1/rmse_' + exp_leaf + '_1.npy')
    drz_rmse = np.load('/Users/santer/dart-nle/experiments/output/' +
                       exp_name + '1/rmse_' + exp_leaf + '_1.npy')
    len_rmse = len(drz_rmse)
    found_drz = True
except FileNotFoundError:
    print("drz rmse file not found")
    num_not_found += 1

try:
    kar_rmse = np.load('/Users/santer/dart-nle/experiments/output/' +
                       exp_name + '2/rmse_' + exp_leaf + '_2.npy')
    len_rmse = len(kar_rmse)
    found_kar = True
except FileNotFoundError:
    print("kar rmse file not found")
    num_not_found += 1

try:
    big_rmse = np.load('/Users/santer/dart-nle/experiments/output/' +
                       exp_name + '4/rmse_' + exp_leaf + '_4.npy')
    len_rmse = len(big_rmse)
    found_big = True
except FileNotFoundError:
    print("big rmse file not found")
    num_not_found += 1

try:
    cnt_rmse = np.load('/Users/santer/dart-nle/experiments/output/' +
                       exp_name + '0/rmse_' + exp_leaf + '_0.npy')
    len_rmse = len(cnt_rmse)
    found_cnt = True
except FileNotFoundError:
    print("cnt rmse file not found")
    num_not_found += 1

try:
    bigs_rmse = np.load('/Users/santer/dart-nle/experiments/output/' +
                       exp_name + '3/rmse_' + exp_leaf + '_3.npy')
    len_rmse = len(bigs_rmse)
    found_bigs = True
except FileNotFoundError:
    print("bigs rmse file not found")
    num_not_found += 1

if num_not_found == 5:
    raise FileNotFoundError("None of the requested files were found.")

if not found_drz:
    drz_rmse = np.zeros(len_rmse)
if not found_kar:
    kar_rmse = np.zeros(len_rmse)
    print(kar_rmse[0])
if not found_big:
    big_rmse = np.zeros(len_rmse)
    print(big_rmse[0])
if not found_bigs:
    bigs_rmse = np.zeros(len_rmse)
    print(bigs_rmse[0])
if not found_cnt:
    cnt_rmse = np.zeros(len_rmse)
    print(cnt_rmse[0])

print(drz_rmse)

datasets = (drz_rmse, kar_rmse, bigs_rmse, big_rmse, cnt_rmse)
DRZ = 0
KAR = 1
ABIGS = 2
ABIGNS = 3
CNT = 4

methods = ['DBCP', 'KAR', 'ABIG-S','ABIG', 'No Estimation']
expts = ['Control Run', 'Underestimated Variance',
         'Overestimed Variance', 'Logistic Error', 'Lognormal Error', 'Biased Gaussian', 'BC_Lognormal']
exp_flag = 0

if exp_leaf == 'gaussian_high':
    exp_flag = 1
elif exp_leaf == 'gaussian_low':
    exp_flag = 2
elif exp_leaf == 'logistic':
    exp_flag = 3
elif exp_leaf == 'lognormal':
    exp_flag = 4
elif exp_leaf == 'biased_gaussian':
    exp_flag = 5
elif exp_leaf == 'lognormal_bias_removed':
    exp_flag = 6


rmsefig, rmseax = plt.subplots()

for d in [0, 1, 2, 4]:
    print("onto methods {}".format(methods[d]))

    # setup
    plot_vals = datasets[d]
    print(plot_vals[:5])
    plot_vals_mean = plot_vals.mean()
    plot_vals_mean = np.format_float_positional(plot_vals_mean, precision=3)

    rmseax.plot(np.arange(len(plot_vals)), plot_vals, label=methods[d] +
                "(average=" + str(plot_vals_mean) + ")", alpha=0.75)

rmseax.set_xlabel('Assimilation Step')
rmseax.set_ylabel('T-B RMSE')

rmseax.set_title("RMSEs - " + exp_name)
rmseax.legend()
rmsefig.savefig('/Users/santer/dart-nle/experiments/output/'+model+'/' + 'run_'+
                       exp_leaf + '/rmses.png')
plt.close(rmsefig)
