import pydartdiags.obs_sequence.obs_sequence as obsq
import sys

print(sys.argv)
input_obs_seq_out = sys.argv[1]
n = int(sys.argv[2])
output_obs_seq_out = sys.argv[3]

obs_seq = obsq.ObsSequence(input_obs_seq_out)
obs_seq_small = obsq.ObsSequence(input_obs_seq_out)

do = len(obs_seq.df)/n
for i in range(n):
    start = int(do*i)
    end = int(do*(i+1))
    obs_seq_small.df = obs_seq.df[start: end].copy()
    obs_seq_small.df['seconds'] -= i * 18000
    obs_seq_small.df.loc[obs_seq_small.df.seconds < 0, 'days'] -= 1
    obs_seq_small.df.loc[obs_seq_small.df.seconds < 0, 'seconds'] += 86400
    obs_seq_small.write_obs_seq('{}.{}'.format(output_obs_seq_out, i+1))
    
