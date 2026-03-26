import sys
import re
import os
import numpy as np
import warnings

DO_NOTHING = 0
PERFECT_OBS = 1
LOGISTIC = 2
STATE_DEP = 3
LOGNORMAL = 4
GAUSSIAN_HIGH_VAR = 5
GAUSSIAN_LOW_VAR = 6
BIASED_GAUSSIAN = 7
LOGNORMAL_BIAS_REMOVED = 8

# constants for quick computation of lognormals with appropriate mean/variance
LN_SIGMA = np.sqrt(np.log(5))
LN_MU = - LN_SIGMA * LN_SIGMA/2


fname = sys.argv[1]
ERROR_FLAG = int(sys.argv[2])
# fname = '/Users/santer/dart-home/dart/models/lorenz_04/work/obs_seq.out'
# ERROR_FLAG = 5

# print("Running nongaussian_error.py with flag " + str(ERROR_FLAG))

rng = np.random.default_rng(58)
# rng = np.random.default_rng(10301)
# rng = np.random.default_rng(11)
pattern = re.compile('\s*OBS\s*\d+')


def gen_obs_with_error(true_val, flag):

    if flag == PERFECT_OBS:
        return true_val
    elif flag == LOGISTIC:
        # for variance = 2:  0.77969680
        # for variance = 4:  1.10265779084
        return true_val + logistic_error(0, 1.10265779084, 20)
    elif flag == STATE_DEP:
        # state, cutoff, m1, v1, m2, v2
        return true_val + state_dependent_error(true_val, 0, 2, 1, -2, 1)
    elif flag == LOGNORMAL:
        # mean, STANDARD DEVIATION, upper bound
        return true_val + lognormal_error(LN_MU, LN_SIGMA)
    elif flag == GAUSSIAN_HIGH_VAR:
        # m, v
        return true_val + gaussian_error(0, 4)
    elif flag == GAUSSIAN_LOW_VAR:
        # m, v
        return true_val + gaussian_error(0, .75)
    elif flag == BIASED_GAUSSIAN:
        # m, v
        return true_val + gaussian_error(1.0, 4)
    elif flag == LOGNORMAL_BIAS_REMOVED:
        # mean, STANDARD DEVIATION
        # same as experiment LOGNORMAL but with mean 0
        return true_val + lognormal_error(LN_MU, LN_SIGMA) - 1


def get_output_filename(flag, name_stem):
    error_type = ''
    if flag == DO_NOTHING:
        error_type = '.control'
    elif flag == PERFECT_OBS:
        error_type = '.perfect'
    elif flag == LOGISTIC:
        error_type = '.logistic'
    elif flag == STATE_DEP:
        error_type = '.state_dep_gaussians'
    elif flag == LOGNORMAL:
        error_type = '.lognormal'
    elif flag == GAUSSIAN_HIGH_VAR:
        error_type = '.gaussian_high'
    elif flag == GAUSSIAN_LOW_VAR:
        error_type = '.gaussian_low'
    elif flag == BIASED_GAUSSIAN:
        error_type = '.biased_gaussian'
    elif flag == LOGNORMAL_BIAS_REMOVED:
        error_type = '.lognormal_bias_removed'
    return name_stem + error_type


# heavy tailed distribution
def logistic_error(loc, scale, bound):
    logistic = rng.logistic(loc, scale)
    return logistic


# state dependent gaussian error
def state_dependent_error(state, cutoff, m1, v1, m2, v2):
    s1 = np.sqrt(v1)
    s2 = np.sqrt(v2)
    if(state > cutoff):
        return rng.normal(m1, s1)
    else:
        return rng.normal(m2, s2)

# TODO lognormal

# given parameters are of underlying normal


def lognormal_error(mu, sigma, bound=None):
    lognormal = rng.lognormal(mean=mu, sigma=sigma)
    if bound is not None:
        while lognormal > bound:
            lognormal = rng.lognormal(mean=mu, sigma=sigma)
    return lognormal


def gaussian_error(m, v):
    s = np.sqrt(v)
    return rng.normal(m, s)

# #################################################


fname_out = get_output_filename(ERROR_FLAG, fname)

if ERROR_FLAG == DO_NOTHING:
    warnings.warn("DO_NOTHING flag set; not modifying " + fname)
    os.system('cp ' + fname + ' ' + fname_out)
    exit()

with open(fname, 'r+') as ofile:
    text = ofile.read()
    text = text.split('\n')

    for line_no in range(len(text)):
        if pattern.match(text[line_no]):
            truth = float(text[line_no + 2])
            obs = gen_obs_with_error(truth, ERROR_FLAG)
            text[line_no + 1] = str(obs)

    text = text[:-1]


with open(fname_out, 'w') as ofile:
    pass

with open(fname_out, 'a') as ofile:
    for line in text:
        ofile.write(f"{line}\n")
