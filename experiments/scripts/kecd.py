from scipy.special import logsumexp
from sklearn.neighbors import NearestNeighbors
import scipy.sparse as sps
import scipy.sparse.linalg as spsl
from scipy.spatial.distance import pdist, squareform, cdist
import numpy as np
from scipy.stats import gaussian_kde
from scipy.linalg import inv


import warnings

def diff_map_ext_nystrom(Xnew, Xtrain, V, D, alphaTrain, chosenBw, knn, Ns):


      N, M = Xtrain.shape
      N2 = Xnew.shape[0]
      
      Ndims = np.ndim(Xnew)
      if Ndims == 1:
            Xnew = np.expand_dims(Xnew, axis=0)  # Add a new first dimension
            
      Xtrain_scaled = Xtrain.copy()
      Xnew_scaled = Xnew.copy()
      
      Xtrain_scaled[:, :Ns] = Xtrain_scaled[:, :Ns] / Ns
      Xnew_scaled[:, :Ns] = Xnew_scaled[:, :Ns] / Ns
            
            
      for j in range(M):
            denom = np.max(np.abs(Xtrain[:, j]))
            if denom > 0:
                  Xtrain_scaled[:, j] /= denom
                  Xnew_scaled[:, j] /= denom
                        
                        
      dist_mat = cdist(Xnew_scaled, Xtrain_scaled)
      sorted_idx = np.argsort(dist_mat, axis=1)
      knn = min(knn, N)
                        
      W_yi = np.zeros((N2, N))
      for iNew in range(N2):
            nbrs = sorted_idx[iNew, :knn]
            dist_sub = dist_mat[iNew, nbrs]
            W_yi[iNew, nbrs] = np.exp(-dist_sub**2 / chosenBw)
                              
      row_sum_new = W_yi @ (alphaTrain**2)
      alphaNew = 1.0 / np.sqrt(row_sum_new)
                              
      T = W_yi * alphaTrain.T
      
      T *= alphaNew
      # T *= alphaNew[:, np.newaxis]
      
      Vnew = T @ V
      Vnew /= D
      
      Vnew *= np.mean(alphaTrain)
                              
      return Vnew

def choose_optimal_epsilon_BGH(scaled_distsq, epsilons=None):
    """
    Calculates the optimal epsilon for kernel density estimation according to
    the criteria in Berry, Giannakis, and Harlim.

    Parameters
    ----------
    scaled_distsq : numpy array
        Values for scaled distance squared values, in no particular order or shape. (This is the exponent in the Gaussian Kernel, aka the thing that gets divided by epsilon).
    epsilons : array-like, optional
        Values of epsilon from which to choose the optimum.  If not provided, uses all powers of 2. from 2^-40 to 2^40

    Returns
    -------
    epsilon : float
        Estimated value of the optimal length-scale parameter.
    d : int
        Estimated dimensionality of the system.

    Notes
    -----
    This code explicitly assumes the kernel is gaussian, for now.

    References
    ----------
    The algorithm given is based on [1]_.  If you use this code, please cite them.

    .. [1] T. Berry, D. Giannakis, and J. Harlim, Physical Review E 91, 032915
       (2015).
    """
    if epsilons is None:
        epsilons = 2**np.arange(-40., 41., 1.)

    epsilons = np.sort(epsilons).astype('float')
    log_T = [logsumexp(-scaled_distsq/(eps)) for eps in epsilons]
    log_eps = np.log(epsilons)
    log_deriv = np.diff(log_T)/np.diff(log_eps)
    max_loc = np.argmax(log_deriv)
    # epsilon = np.max([np.exp(log_eps[max_loc]), np.exp(log_eps[max_loc+1])])
    epsilon = np.exp(log_eps[max_loc])
    d = np.round(2.*log_deriv[max_loc])
    return epsilon, d

def dmap_hms(data, Neig, knn, bw, Ns, alpha, f_normalize=True, symmetric_row_normalize=True):

    print(np)

    def gaussian_k(d, bw):
        return np.exp(-d**2 / bw)
    
    rng = np.random.default_rng(58)
    N,M = data.shape
    scaled_data = data.copy()
    if f_normalize:
        for i in range(M):
            denom = np.max(np.abs(scaled_data[:, i]))
            if denom > 0:
                scaled_data[:, i] /= denom
    sknn = NearestNeighbors(n_neighbors=knn, n_jobs=-1, algorithm='ball_tree')
    sknn.fit(scaled_data)
    dists = sknn.kneighbors_graph(scaled_data, mode='distance')
    
    K = dists.copy()

    if bw=='adaptive':
          bw, max_d = choose_optimal_epsilon_BGH(K.data ** 2)
          bw *= 2
          print(bw)
    
    K.data = gaussian_k(dists.data, bw)
    Ksym = (K.T).maximum(K)

    # alpha normalization
    q = np.array(K.sum(axis=1)).ravel()
    right_norm_vec = np.power(q, -alpha)
    m = right_norm_vec.shape[0]
    Dalpha = sps.spdiags(right_norm_vec, 0, m, m)
    K_rn = Ksym @ Dalpha

    # row normalization
    if symmetric_row_normalize:
        row_sum = K_rn.sum(axis=1).transpose()
        inv_row_sum = np.power(row_sum, -0.5)
        n = row_sum.shape[1]
        Dalpha = sps.spdiags(inv_row_sum, 0, n, n)
        P = Dalpha @ K_rn @ Dalpha
    else:
        row_sum = K_rn.sum(axis=1).transpose()
        inv_row_sum = np.power(row_sum, -1)
        n = row_sum.shape[1]
        Dalpha = sps.spdiags(inv_row_sum, 0, n, n)
        P = Dalpha * K_rn

      
    # P = (P.T).maximum(P)  # Ensure symmetr
    P = P + 1e-10 * np.eye(n)
    
    evals, evecs = spsl.eigs(P, k=Neig+1, which='LR')

    # Eigen decomposition
    # v0 = rng.uniform(0, 1, n)
    # try:
    #     evals, evecs = eigsh(P, k=Neig + 1, sigma=1.0001, which="LM", v0=v0)
    # except apnc as e:
    #     evals = e.eigenvalues
    #     evecs = e.eigenvectors
    #     print(f'Only found {len(evals)} out of {Neig + 1} eigenvectors')


    # evals = np.real(evals)
    # evecs = np.real(evecs)
   
    # evecs = (evecs.T[np.argsort(evals)][::-1]).T
    # evals = evals[np.argsort(evals)][::-1]

    ix = evals.argsort()[::-1][:]
    evals = np.real(evals[ix])
    evecs = np.real(evecs[:, ix])
    return evecs, evals, inv_row_sum, bw, scaled_data
 

def rkhs_likelihood(a, b, Neig, knn, klb, bw, Ns, train_frac):


      N = a.shape[0]
      a_cop = a.copy()
      b_cop = b.copy()

      # Get eigenvectors and eigenvalues of diffusion maps
      # Vb, Db, a_train_b, bwb, keeps = diff_map(b_cop, Neig, knn, bw, 0.01, Ns, train_frac, plotW=True, klb=klb)
      # Va, Da, a_train_a, bwa, keeps = diff_map(a_cop, Neig, knn, bw, 0.01, 1, train_frac, keeps, klb=klb)
      
      # HMS TESTING 12/1
      Vb, Db, a_train_b, bwb, keeps = dmap_hms(b_cop, Neig, knn, bw, Ns, 0, f_normalize=True, symmetric_row_normalize=True)
      Va, Da, a_train_a, bwa, keeps = dmap_hms(a_cop, Neig, knn, bw, 1, 0, f_normalize=True, symmetric_row_normalize=True)
      # HMS END TESTING 12/1


      a_signs = np.where(Va[0] < 0, -1, 1)
      Va *= a_signs
      b_signs = np.where(Vb[0] < 0, -1, 1)
      Vb *= b_signs

      x_emb = (Vb * Db).T
      y_emb = (Va * Da).T

      # a_cop = a_cop[keeps]
      # b_cop = b_cop[keeps]

      # TODO WHATS THIS FOR
      # for i in range(a_cop.shape[1]):
          # varb[i] = (np.sqrt(varb[i]) / np.max(np.abs(a[:, i]))) ** 2
          # a_cop[:, i] /= np.max(np.abs(a_cop[:, i]))

      # kde = gaussian_kde(a_cop.T, bw_method=bwa/a_cop.std(ddof=1))
      kde = gaussian_kde(a_cop.T, bw_method='scott')
      qa = kde(a_cop.T)

      # Calculate kernel mean embeddings
      N, M1 = Va.shape
      N, M2 = Vb.shape
      
      Va *= Da
      Vb *= Db

      Cab = (Va.T @ Vb) / N
      Cbb = (Vb.T @ Vb) / N

      C = Cab @ inv(Cbb, overwrite_a=True)
      Mu = (Vb @ C.T)
      
      # Compute pab
      
      pab = (Va @ Mu.T) * qa[:, np.newaxis]
      
      # Remove imaginary and negative values
      pab[pab < 0] = 0
      pab = np.real(pab)

      return pab, (Vb, Db, a_train_b, bwb), (Va, Da, a_train_a, bwa), keeps
