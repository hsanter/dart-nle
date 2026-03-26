
n_obs = 40
obs_err_var = 1

with open("cos_input.txt", "w") as f:
    f.write('{}\n0\n0\n'.format(n_obs))

with open("cos_input.txt", "a") as f:

    for i in range(n_obs):
        f.write('0\n1\n')
        f.write('{}\n'.format(i/n_obs))
        f.write('0 0\n1\n')
        
    f.write('set_def.out')
