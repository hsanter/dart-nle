import pydartdiags.obs_sequence.obs_sequence as obsq
import numpy as np
import sys

input_obs_seq_out = sys.argv[1]
n = int(sys.argv[2])
output_obs_seq_out = sys.argv[3]

chunk_len_secs = int(sys.argv[4])
chunk_len_days = int(sys.argv[5])

obs_sqs = []

for i in range(1,n+1):
    chunk = obsq.ObsSequence(input_obs_seq_out + '{}'.format(i))
    chunk.df['days'] += (i-1) * chunk_len_days
    chunk.df['seconds'] += (i-1) * chunk_len_secs
    chunk.df['time'] += np.timedelta64((i-1) * chunk_len_days, 'D')
    chunk.df['time'] += np.timedelta64((i-1) * chunk_len_secs, 's')
    obs_sqs.append(chunk)
    
obs_seq_full = obsq.ObsSequence.join(obs_sqs)

obs_seq_full.write_obs_seq(output_obs_seq_out)
    
