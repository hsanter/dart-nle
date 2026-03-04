import pydartdiags.obs_sequence.obs_sequence as obsq
import numpy as np
import sys
import kecd
import matplotlib.pyplot as plt
from scipy.stats import norm

input_obs_seq_final = sys.argv[1]
curr_time = int(sys.argv[2])
n_train = int(sys.argv[3])
output_pab_file = sys.argv[4]
train_on_truth = bool(sys.argv[5])
bw = np.float64(sys.argv[6])
knnf = np.float64(sys.argv[7])

chunk_len_days = 0
chunk_len_secs = 18000
obs_sqs = []

for i in range(curr_time - n_train+1,curr_time+1):
    chunk = obsq.ObsSequence(input_obs_seq_final + '{}'.format(i))
    chunk.df['days'] += (i-1) * chunk_len_days
    chunk.df['seconds'] += (i-1) * chunk_len_secs
    chunk.df['time'] += np.timedelta64((i-1) * chunk_len_days, 'D')
    chunk.df['time'] += np.timedelta64((i-1) * chunk_len_secs, 's')
    obs_sqs.append(chunk)
    
obs_seq_train = obsq.ObsSequence.join(obs_sqs)

cols = ['posterior_ensemble_member_{}'.format(i) for i in range(1,41)]
np.random.seed(58)
obs_seq_train.df["random_posterior_draw"] = obs_seq_train.df[cols].to_numpy()[
    np.arange(len(obs_seq_train.df)),
    np.random.randint(0, len(cols), size=len(obs_seq_train.df))
]

y_train = obs_seq_train.df['observation'].values.reshape((len(obs_seq_train.df), -1)).T

if train_on_truth:
    x_train = obs_seq_train.df['truth'].values.reshape((len(obs_seq_train.df), -1)).T
else:
    x_train = obs_seq_train.df['random_posterior_draw'].values.reshape((len(obs_seq_train.df), -1)).T

knn = len(y_train.T) * knnf

pyx, x_emb, y_emb, keeps = kecd.rkhs_likelihood(y_train.T, x_train.T, 50, knn, 0.0, bw, 1, 1)

np.savez(output_pab_file, pyx = pyx, x_map=x_map, y_map=y_map)
