export n=$1

cp input.nml input.nml.orig

python join_obs_seqs.py "output_chunks/obs_seq.final.${postf}." "${n}" "output_chunks/obs_seq.final.${postf}.joined" ${chunk_len_secs} ${chunk_len_days}

sed \
    -e "s/filename_seq[[:space:]]*=[[:space:]]*'obs_seq.out',/filename_seq         = 'obs_seq.final.${postf}.joined',/" \
    -e "s/filename_out[[:space:]]*=[[:space:]]*'obs_seq.out.grouped'/filename_out         = 'obs_seq.final.${postf}.joined'/" \
    input.nml.orig > input.nml.edit
mv input.nml.edit input.nml

mv output_chunks/obs_seq.final.${postf}.joined .
./obs_grouping_tool
mv obs_seq.final.${postf}.joined output_chunks/

rm input.nml.orig
rm dart_log.nml
rm dart_log.out
