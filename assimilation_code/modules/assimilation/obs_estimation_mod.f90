!!$ DART software - Copyright UCAR (??) Henry Santer, fall 2023. subroutines for online/offline estimation of
! observation error variance


module obs_estimation_mod

use        types_mod, only : r8, i8, MISSING_R8, metadatalength, obstypelength, PI

use     location_mod, only : location_type, is_location_in_region, set_location

use      obs_def_mod, only : obs_def_type, get_obs_def_time, read_obs_def,           &
                             write_obs_def, destroy_obs_def, copy_obs_def,           &
                             interactive_obs_def, get_obs_def_location,              &
                             get_obs_def_type_of_obs, get_obs_def_key,               &
                             get_obs_def_error_variance, set_obs_def_error_variance, &
                             get_obs_def_time,                                       &
                             operator(==), operator(/=), print_obs_def

use assim_model_mod,       only : static_init_assim_model, get_model_size,                    &
                                  end_assim_model,  pert_model_copies, get_model_time_step

use adaptive_inflate_mod,   only : change_GA_IG, solve_quadratic

use     obs_kind_mod, only : write_type_of_obs_table,   &
                             read_type_of_obs_table,    &
                             max_defined_types_of_obs,  &
                             get_index_for_type_of_obs, &
                             get_name_for_type_of_obs

use time_manager_mod, only : time_type, set_time, print_time, print_date, &
                             operator(-), operator(+), &
                             operator(>), operator(<), &
                             operator(>=), operator(/=), operator(==)

use    utilities_mod, only : get_unit, error_handler, &
                             find_namelist_in_file, check_namelist_read, &
                             E_ERR, E_MSG, nmlfileunit, do_nml_file, do_nml_term, &
                             open_file, close_file

use obs_sequence_mod, only : obs_sequence_type, init_obs_sequence, interactive_obs_sequence, &
                             get_num_copies, get_num_qc, get_num_obs, get_max_num_obs, &
                             get_copy_meta_data, get_qc_meta_data, get_next_obs, get_prev_obs, &
                             insert_obs_in_seq, delete_obs_from_seq, set_copy_meta_data, &
                             set_qc_meta_data, add_copies, add_qc, &
                             write_obs_seq, read_obs_seq, set_obs, append_obs_to_seq, &
                             get_obs_from_key, get_obs_time_range, get_time_range_keys, &
                             get_num_times, get_num_key_range, operator(==), operator(/=), &
                             static_init_obs_sequence, destroy_obs_sequence, read_obs_seq_header, &
                             delete_seq_head, delete_seq_tail, &
                             get_next_obs_from_key, get_prev_obs_from_key, delete_obs_by_typelist, &
                             select_obs_by_location, delete_obs_by_qc, delete_obs_by_copy, &
                             obs_type, init_obs, destroy_obs, get_obs_def, set_obs_def, &
                             get_obs_values, set_obs_values, replace_obs_values, get_qc, set_qc, &  
                             read_obs, write_obs, replace_qc, interactive_obs, copy_obs, assignment(=), &
                             get_obs_key, copy_partial_obs, print_obs, &
                             print_obs_seq_summary, validate_obs_seq_time, obs_subset_def_type, &
                             get_obs_time_range_subset, get_obs_subset_variance, set_obs_subset_variance, &
                             get_obs_subset_num, obs_subset_type


implicit none
private
                            

public :: update_subset_variances_preassim, update_subset_variances_postassim, &
     obs_estimation_init, use_variance_estimates, do_variance_estimation,  &
     do_prior_obs_estimation, do_posterior_obs_estimation, obs_estimation_type,&
     get_subset_variances, set_subset_variances


!-------------------------------------------------------------------------------

character(len=*), parameter :: source = 'obs_estimation_mod.f90'

integer, parameter :: NO_ESTIMATION            = 0
integer, parameter :: OA_OB_ESTIMATION         = 1
integer, parameter :: OB_STATE_VAR_ESTIMATION  = 2
integer, parameter :: BAYES_INFLATE_ESTIMATION = 3

! this feels sloppy but I'm not sure what to do instead - maybe ask during code review?
! either this or we make some of the sizes below all set at runtime? i guess
! we can also drop this in obs_estimation_mod_nml?
integer, parameter :: MAX_OBS_ESTIMATION_SUBSETS = 100

!!$ temporary for writing debug stuff
integer :: debugfileunit = 58
integer :: debugfileunitd = 60
integer :: debugfileunita = 59

type obs_estimation_type
   private
   integer              :: obs_estimation_flavor
   real(r8)             :: smoothing, sd_max_change
   real(r8)             :: sd_lower_bound, rho_lower_bound, rho_upper_bound
   real(r8)             :: initial_variances(MAX_OBS_ESTIMATION_SUBSETS)
   real(r8)             :: current_variances(MAX_OBS_ESTIMATION_SUBSETS)
   real(r8)             :: obs_inflate(MAX_OBS_ESTIMATION_SUBSETS)
   real(r8)             :: sd(MAX_OBS_ESTIMATION_SUBSETS)
   logical              :: use_variances
   integer              :: prior_obs_mean_index, posterior_obs_mean_index, observation_index
   integer              :: prior_obs_spread_index, DART_qc_index
   integer              :: ens_size
   type(time_type)      :: estimation_window_width
end type obs_estimation_type


character(len=512)   :: msgstring
integer              :: obs_estimation_flavor
real(r8)             :: temporal_smoothing, sd_max_change
real(r8)             :: sd, sd_lower_bound, rho_lower_bound, rho_upper_bound
real(r8)             :: initial_variances(MAX_OBS_ESTIMATION_SUBSETS)
real(r8)             :: current_variances(MAX_OBS_ESTIMATION_SUBSETS)
real(r8)             :: initial_obs_inflate(MAX_OBS_ESTIMATION_SUBSETS)
real(r8)             :: initial_obs_inflate_sd(MAX_OBS_ESTIMATION_SUBSETS)
logical              :: use_variances
integer              :: prior_obs_mean_index, posterior_obs_mean_index, observation_index
integer              :: prior_obs_spread_index, DART_qc_index
integer              :: ens_size
integer              :: window_width_seconds, window_width_days

! Flag indicating whether module has been initialized
logical :: initialized = .false.
logical :: one_assimilation_done_before_preassim_estimation = .false.

! Used for precision tests in inflation update routines
real(r8), parameter    :: small = epsilon(1.0_r8)   ! threshold for avoiding NaNs/Inf


namelist /obs_estimation_nml/ temporal_smoothing, obs_estimation_flavor, &
     window_width_days, window_width_seconds, use_variances, rho_lower_bound, &
     sd_lower_bound, initial_obs_inflate, initial_obs_inflate_sd,    &
     rho_upper_bound, sd_max_change


!-------------------------------------------------------------------------------


contains


!-------------------------------------------------------------------------------
!>

! set up estimation handle (called from filter)
subroutine obs_estimation_init(estimation_handle, prior_mean_index, posterior_mean_index, &
     prior_spread_index, obs_index, qc_index, ens_n, subsets, num_subsets)
    
  type(obs_estimation_type),  intent(inout) :: estimation_handle
  integer,                    intent(in)    :: num_subsets
  type(obs_subset_type),  intent(in)    :: subsets(num_subsets)
  integer,                    intent(in)    :: prior_mean_index, posterior_mean_index, obs_index
  integer,                    intent(in)    :: prior_spread_index, qc_index, ens_n

  integer              :: iunit, io, i
  type(time_type)      :: estimation_window_width
  real(r8)             :: initial_variances(MAX_OBS_ESTIMATION_SUBSETS)
  
  ! Record the module version if this is first initialize call
  if(.not. initialized) then
     initialized = .true.
  endif

  call find_namelist_in_file("input.nml", "obs_estimation_nml", iunit)
  read(iunit, nml = obs_estimation_nml, iostat = io)
  call check_namelist_read(iunit, io, "obs_estimation_nml")

  call set_window_width(estimation_window_width, window_width_days, &
       window_width_seconds)

  do i = 1,num_subsets
     estimation_handle%initial_variances(i) = get_obs_subset_variance(subsets(i))
     estimation_handle%current_variances(i) = get_obs_subset_variance(subsets(i))
     estimation_handle%obs_inflate(i) = initial_obs_inflate(i)
     estimation_handle%sd(i) = initial_obs_inflate_sd(i)
  end do

  estimation_handle%obs_estimation_flavor = obs_estimation_flavor
  estimation_handle%prior_obs_mean_index = prior_mean_index
  estimation_handle%posterior_obs_mean_index = posterior_mean_index
  estimation_handle%observation_index = obs_index
  estimation_handle%prior_obs_spread_index = prior_spread_index
  estimation_handle%DART_qc_index = qc_index
  estimation_handle%rho_lower_bound = rho_lower_bound
  estimation_handle%rho_upper_bound = rho_upper_bound
  estimation_handle%sd_lower_bound = sd_lower_bound
  estimation_handle%estimation_window_width = estimation_window_width
  estimation_handle%use_variances = use_variances
  estimation_handle%ens_size = ens_n
  estimation_handle%smoothing = temporal_smoothing
  estimation_handle%sd_max_change = sd_max_change
  
end subroutine obs_estimation_init
  

!-------------------------------------------------------------------------------
!>

subroutine set_window_width(estimation_window_width, window_width_days, window_width_seconds)

  integer,         intent(in)  :: window_width_days
  integer,         intent(in)  :: window_width_seconds
  type(time_type), intent(out) :: estimation_window_width

  if(window_width_seconds == -1 .or. window_width_days == -1)then
     estimation_window_width = get_model_time_step() - set_time(1,0)
  else
     estimation_window_width = set_time(window_width_seconds, window_width_days)
  endif

end subroutine set_window_width


!-------------------------------------------------------------------------------
!>

subroutine update_subset_variances_preassim(estimation_handle, subsets, num_subsets, window_end, seq)

  type(obs_subset_type), intent(inout) :: subsets(num_subsets)
  type(obs_estimation_type), intent(inout) :: estimation_handle
  type(obs_sequence_type),   intent(in)    :: seq
  type(time_type),           intent(in)    :: window_end
  integer,                   intent(in)    :: num_subsets

  integer              :: key_bounds(2)
  integer              :: num_obs_in_subset
  integer              :: i, j
  logical              :: out_of_range
  integer, allocatable :: subset_keys(:)
  type(time_type)      :: window_start


  ! HMS this works well for 1d models that DART can run on its own, but the way that
  ! this is handled for larger models needs to be addressed still.
  if(.not. one_assimilation_done_before_preassim_estimation) then
     msgstring= 'Skipping pre-assimilation obs variance estimation until one assimilation cycle is completed'
     call error_handler(E_MSG, 'update_subset_variances_preassim:', msgstring, source)
     one_assimilation_done_before_preassim_estimation = .true.
     return
  endif
  
  if(estimation_handle%estimation_window_width > window_end)then
     msgstring= 'Estimation window larger than elapsed time so far. Not starting obs variance estimation yet.'
     call error_handler(E_MSG, 'update_subset_variances_preassim:', msgstring, source)
     return
  endif

  window_start = window_end - estimation_handle%estimation_window_width

  do i = 1, num_subsets

     call get_obs_time_range_subset(seq, window_start, window_end, key_bounds, &
          num_obs_in_subset, out_of_range, subsets(i), estimation_handle%DART_qc_index)

     if(num_obs_in_subset == 0) then
        msgstring = 'No obs in current window within this subset - advancing.'
        call error_handler(E_MSG, 'update_subset_variances_postassim:', msgstring, source)
        cycle
     endif

     allocate(subset_keys(num_obs_in_subset))

     call get_time_range_keys(seq, key_bounds, num_obs_in_subset, &
          subset_keys, subsets(i))

     if(estimation_handle%obs_estimation_flavor == OB_STATE_VAR_ESTIMATION) then
        call karspeck_update(estimation_handle, subset_keys, num_obs_in_subset, seq, &
             subsets(i), estimation_handle%current_variances(i))

     else if(estimation_handle%obs_estimation_flavor == BAYES_INFLATE_ESTIMATION) then
        call bayes_obs_batch_update(estimation_handle, subset_keys, num_obs_in_subset, seq, &
             subsets(i), estimation_handle%current_variances(i))
     endif

     deallocate(subset_keys)
     
  enddo
end subroutine update_subset_variances_preassim

!-------------------------------------------------------------------------------
!>

subroutine update_subset_variances_postassim(estimation_handle, subsets, num_subsets, window_end, seq)

  type(obs_subset_type), intent(inout) :: subsets(num_subsets)
  type(obs_estimation_type), intent(inout) :: estimation_handle
  type(obs_sequence_type),   intent(in)    :: seq
  type(time_type),           intent(in)    :: window_end
  integer,                   intent(in)    :: num_subsets
!!$
  integer :: key_bounds(2)
  integer :: num_obs_in_subset
  integer, allocatable :: subset_keys(:)
  integer :: i, j
  logical :: out_of_range
  type(time_type)  :: window_start


  if(estimation_handle%estimation_window_width > window_end)then
     msgstring= 'Estimation window larger than elapsed time so far. Not starting obs variance estimation yet.'
     call error_handler(E_MSG, 'update_subset_variances_postassim:', msgstring, source)
  endif

  window_start = window_end - estimation_handle%estimation_window_width

  do i = 1, num_subsets

     call get_obs_time_range_subset(seq, window_start, window_end, key_bounds, &
          num_obs_in_subset, out_of_range, subsets(i), estimation_handle%DART_qc_index)

     if(num_obs_in_subset == 0) then
        msgstring = 'No obs in current window within this subset - advancing.'
        call error_handler(E_MSG, 'update_subset_variances_postassim:', msgstring, source)
        cycle
     endif

     allocate(subset_keys(num_obs_in_subset))

     call get_time_range_keys(seq, key_bounds, num_obs_in_subset, &
          subset_keys, subsets(i), estimation_handle%DART_qc_index)

     if(obs_estimation_flavor == OA_OB_ESTIMATION) then
        call desroziers_oa_ob_update(estimation_handle, subset_keys, num_obs_in_subset, seq, subsets(i), &
             estimation_handle%current_variances(i))
     endif
     ! add an else here if there are other options

     deallocate(subset_keys)
     
  enddo

end subroutine update_subset_variances_postassim


!-------------------------------------------------------------------------------
!>

subroutine desroziers_oa_ob_update(estimation_handle, keys, num_obs_in_subset, seq, subset, smoothed_variance)

  type(obs_estimation_type), intent(inout) :: estimation_handle
  type(obs_subset_type), intent(inout) :: subset
  type(obs_sequence_type),   intent(in)    :: seq
  integer,                   intent(in)    :: num_obs_in_subset
  integer,                   intent(in)    :: keys(num_obs_in_subset)
  real(r8),                  intent(out)   :: smoothed_variance

  real(r8) :: temp_observation(1)
  real(r8) :: temp_analysis(1)
  real(r8) :: temp_background(1)
  real(r8) :: observations(num_obs_in_subset) 
  real(r8) :: analysis(num_obs_in_subset)
  real(r8) :: background(num_obs_in_subset)
  real(r8) :: new_variance

  integer        :: i
  type(obs_type) :: temp_obs


!!$  open(unit = debugfileunitd, file = "dbcp_issues.log", action='write', position='append',status='unknown')
  ! should i have a separate function grab all of the prior/posterior means/observations that
  ! gets called in the three different update functions? there's overlapping code here that all
  ! does the same thing in here + the next two subroutines
  do i=1, num_obs_in_subset

     call get_obs_from_key(seq, keys(i), temp_obs)
     call get_obs_values(temp_obs, temp_observation, estimation_handle%observation_index)
     call get_obs_values(temp_obs, temp_background, estimation_handle%prior_obs_mean_index)
     call get_obs_values(temp_obs, temp_analysis, estimation_handle%posterior_obs_mean_index)

     observations(i) = temp_observation(1)
     background(i) = temp_background(1)
     analysis(i) = temp_analysis(1)

  enddo

  new_variance =  dot_product(observations - background, observations - analysis) &
       /num_obs_in_subset

  if(new_variance < 0.0_r8) then
!!$     write(debugfileunitd, *), new_variance
     smoothed_variance = get_obs_subset_variance(subset)
  else
!!$     write(debugfileunitd, *), "good!"
     smoothed_variance = estimation_handle%smoothing * new_variance + &
          (1.0_r8 - estimation_handle%smoothing) * get_obs_subset_variance(subset)
  endif

  ! for debugging, but maybe it makes sense to periodically output variance estimates during DA?
  ! or log them out to a file somewhere 
  print *, "============"
  print *, "next variance", smoothed_variance
  
  call set_obs_subset_variance(subset, smoothed_variance)
!!$  close(debugfileunitd)

end subroutine desroziers_oa_ob_update
   

subroutine karspeck_update(estimation_handle, keys, num_obs_in_subset, seq, subset, smoothed_variance)

  type(obs_subset_type), intent(inout) :: subset
  type(obs_estimation_type), intent(inout) :: estimation_handle
  type(obs_sequence_type),   intent(in)    :: seq
  integer,                   intent(in)    :: num_obs_in_subset
  integer,                   intent(in)    :: keys(num_obs_in_subset)
  real(r8),                  intent(out)   :: smoothed_variance

  real(r8) :: temp_observation(1)
  real(r8) :: temp_background(1)
  real(r8) :: temp_spread(1)
  real(r8) :: observations(num_obs_in_subset) 
  real(r8) :: background(num_obs_in_subset)
  real(r8) :: prior_spread(num_obs_in_subset)
  real(r8) :: prior_var(num_obs_in_subset)
  real(r8) :: new_variance
  real(r8) :: innovation_term
  real(r8) :: model_variance_term

  integer        :: i
  type(obs_type) :: temp_obs

!!$  open(unit = debugfileunit, file = "kp_issues.log", action='write', position='append',status='unknown')

  do i=1, num_obs_in_subset

     call get_obs_from_key(seq, keys(i), temp_obs)
     call get_obs_values(temp_obs, temp_observation, estimation_handle%observation_index)
     call get_obs_values(temp_obs, temp_background, estimation_handle%prior_obs_mean_index)
     call get_obs_values(temp_obs, temp_spread, estimation_handle%prior_obs_spread_index)

     observations(i) = temp_observation(1)
     background(i) = temp_background(1)
     prior_spread(i) = temp_spread(1)

  enddo

  innovation_term =  dot_product(observations - background, observations - background) &
       /num_obs_in_subset

  prior_var = prior_spread * prior_spread

  model_variance_term = (estimation_handle%ens_size + 1) * sum(prior_var) &
       /(num_obs_in_subset * estimation_handle%ens_size)

  new_variance = innovation_term - model_variance_term

  ! prevent karspeck estimator from going negative
  if(new_variance < 0.0_r8) then
!!$     write(debugfileunit, *), new_variance
     smoothed_variance = get_obs_subset_variance(subset)
  else
!!$     write(debugfileunit, *), "good!"
     smoothed_variance = estimation_handle%smoothing * new_variance + &
          (1.0_r8 - estimation_handle%smoothing) * get_obs_subset_variance(subset)
  endif

  ! for debugging, but maybe it makes sense to periodically output variance estimates during DA?
  ! or log them out to a file somewhere 
  print *, "============"
  print *, "next variance", smoothed_variance
  
  call set_obs_subset_variance(subset, smoothed_variance)
!!$  close(debugfileunit)


end subroutine karspeck_update

subroutine bayes_obs_batch_update(estimation_handle, keys, num_obs_in_subset, seq, subset, smoothed_variance)

  type(obs_subset_type), intent(inout) :: subset
  type(obs_estimation_type), intent(inout) :: estimation_handle
  type(obs_sequence_type),   intent(in)    :: seq
  integer,                   intent(in)    :: num_obs_in_subset
  integer,                   intent(in)    :: keys(num_obs_in_subset)
  real(r8),                  intent(out)   :: smoothed_variance

  real(r8) :: temp_observation(1)
  real(r8) :: temp_background(1)
  real(r8) :: temp_spread(1)
  real(r8) :: temp_var
  real(r8) :: observations(num_obs_in_subset) 
  real(r8) :: background(num_obs_in_subset)
  real(r8) :: old_obs_inflate, old_obs_inflate_sd
  real(r8) :: new_obs_inflate, new_obs_inflate_sd
  real(r8) :: sigma_o_2
  real(r8) :: new_variance

  integer        :: i, group_num
  type(obs_type) :: temp_obs

  group_num = get_obs_subset_num(subset)
  sigma_o_2 = estimation_handle%initial_variances(group_num)

  old_obs_inflate = estimation_handle%obs_inflate(group_num)
  old_obs_inflate_sd = estimation_handle%sd(group_num)

!!$  open(unit = debugfileunita, file = "abig_sds.log", action='write', position='append',status='unknown')
  do i=1, num_obs_in_subset

     call get_obs_from_key(seq, keys(i), temp_obs)
     call get_obs_values(temp_obs, temp_observation, estimation_handle%observation_index)
     call get_obs_values(temp_obs, temp_background, estimation_handle%prior_obs_mean_index)
     call get_obs_values(temp_obs, temp_spread, estimation_handle%prior_obs_spread_index)

     temp_var = temp_spread(1) * temp_spread(1)

     call bayes_obs_inflate(temp_var, temp_observation(1), temp_background(1), &
          sigma_o_2, old_obs_inflate, old_obs_inflate_sd, new_obs_inflate, new_obs_inflate_sd, &
          estimation_handle%sd_lower_bound, estimation_handle%sd_max_change)


     ! change to some mins/maxs
     ! checks for maintining constraints on rho distribution
     if(new_obs_inflate < estimation_handle%rho_lower_bound) new_obs_inflate = estimation_handle%rho_lower_bound
     if(new_obs_inflate > estimation_handle%rho_upper_bound) new_obs_inflate = estimation_handle%rho_upper_bound
     
     if(new_obs_inflate_sd < estimation_handle%sd_lower_bound) new_obs_inflate_sd = estimation_handle%sd_lower_bound

     old_obs_inflate = new_obs_inflate
     old_obs_inflate_sd = new_obs_inflate_sd
!!$     write (debugfileunita, *), new_obs_inflate_sd

  enddo

  estimation_handle%obs_inflate(group_num) = new_obs_inflate
  estimation_handle%sd(group_num) = new_obs_inflate_sd
!!$  write (debugfileunita, *), "next batch"
     

!!$  close(debugfileunita)
  new_variance = new_obs_inflate * sigma_o_2


  if(new_variance < 0.0_r8) then
     smoothed_variance = get_obs_subset_variance(subset)
  else
     smoothed_variance = estimation_handle%smoothing * new_variance + &
          (1.0_r8 - estimation_handle%smoothing) * get_obs_subset_variance(subset)
  endif


  call set_obs_subset_variance(subset, smoothed_variance)

end subroutine bayes_obs_batch_update

! HMS everything this function does is in adaptive_inflate_mod/bayes_cov_inflate,
! but we don't need access to a couple state-related variables here
! additionally, the likelihoods used in obs_linear_bayes and
! adaptive_inflate_mod/enh_linear_bayes are different.

subroutine bayes_obs_inflate(sigma_p_2, y_o, x_p, sigma_o_2, rho_mean, rho_sd, &
     new_obs_inflate, new_obs_inflate_sd, sd_lower_bound_in, sd_max_change_in)
  
real(r8), intent(in)  :: x_p, sigma_p_2, y_o, sigma_o_2, rho_mean, rho_sd
real(r8), intent(in)  :: sd_lower_bound_in, sd_max_change_in
real(r8), intent(out) :: new_obs_inflate, new_obs_inflate_sd

real(r8) :: dist_2, rate, shape_old, shape_new, rate_new
real(r8) :: rho_sd_2, density_1, density_2, omega, ratio
real(r8) :: new_1_sd, new_max

! inflation variance
rho_sd_2 = rho_sd ** 2

! squared innovation
dist_2 = (y_o - x_p)**2 

call change_GA_IG(rho_mean, rho_sd_2, rate)

call obs_linear_bayes(dist_2, sigma_p_2, sigma_o_2, rho_mean, &
     rate, new_obs_inflate)

! below snippet is pulled verbatim from adaptive_inflate_mod/bayes_cov_inflate
! up to renaming of variables from state inflation terms to observation inflation
! terms
if(abs(rho_sd - sd_lower_bound_in) <= TINY(0.0_r8)) then
   new_obs_inflate_sd = rho_sd
   return 
else
   ! Compute the shape parameter of the prior IG
   ! This comes from the assumption that the mode of the IG is the mean/mode 
   ! of the input Gaussian
   shape_old = rate / rho_mean - 1.0_r8
   if (shape_old <= 2.0_r8) then
      new_obs_inflate_sd = rho_sd
      return
   endif

   ! Evaluate exact IG posterior at p1: \rho_u+\sigma_{\rho_b} & p2: \rho_u
   ! TODO make this exist
   density_1 = obs_compute_new_density(dist_2, sigma_p_2, sigma_o_2, &
                      shape_old, rate, new_obs_inflate+rho_sd)
   density_2 = obs_compute_new_density(dist_2, sigma_p_2, sigma_o_2, &
                      shape_old, rate, new_obs_inflate)
   
   ! Computational errors check (small numbers + NaNs)
   ! HMS Q: why are there pairs of seemingly identical checks here?
   if (abs(density_1) <= TINY(0.0_r8) .OR. &
       abs(density_2) <= TINY(0.0_r8) .OR. &
       density_1 /= density_1 .OR. density_1 /= density_1 .OR. &
       density_2 /= density_2 .OR. density_2 /= density_2) then
      new_obs_inflate_sd = rho_sd
      return
   endif
   
   ! Now, compute omega and the new distribution parameters
   ratio     = density_1 / density_2
   omega     = log(new_obs_inflate          )/new_obs_inflate + 1.0_r8/new_obs_inflate - &
               log(new_obs_inflate+rho_sd)/new_obs_inflate - 1.0_r8/(new_obs_inflate+rho_sd)
   rate_new  = log(ratio) / omega
   shape_new = rate_new / new_obs_inflate - 1.0_r8
   
   ! Finally, get the sd of the IG posterior
   if (shape_new <= 2.0_r8) then
      new_obs_inflate_sd = rho_sd
      return
   endif
   new_obs_inflate_sd = sqrt(rate_new**2 / ( (shape_new-1.0_r8)**2 * (shape_new-2.0_r8) ))
   
   ! If the updated variance is more than xx% the prior variance, keep the prior variance unchanged 
   ! for stability reasons. Also, if the updated variance is NaN (not sure why this
   ! can happen; never did when developing this code), keep the prior variance unchanged. 
   if ( new_obs_inflate_sd > sd_max_change_in*rho_sd .OR. &
        new_obs_inflate_sd /= new_obs_inflate_sd) then
      new_obs_inflate_sd = rho_sd
      return
   endif
end if

end subroutine bayes_obs_inflate


!-------------------------------------------------------------------------------
!>

! HMS similar to adaptive_inflate_mod/enh_linear_bayes with a different likelihood
! but otherwise the same code/checks
subroutine obs_linear_bayes(dist_2, sigma_p_2, sigma_o_2, &
     rho_mean, beta, new_obs_inflate)

real(r8), intent(in)    :: dist_2, sigma_p_2, sigma_o_2, rho_mean
real(r8), intent(in)    :: beta
real(r8), intent(inout) :: new_obs_inflate

real(r8) :: theta_bar_2, like_bar, like_prime, theta_bar
real(r8) :: a, b, c, plus_root, minus_root, deriv_theta
real(r8) :: fac, like_ratio

! Compute value of theta at current rho_mean
theta_bar_2 = rho_mean * sigma_o_2 + sigma_p_2
theta_bar = sqrt(theta_bar_2)

! Compute constant coefficient for likelihood at rho_bar
like_bar = exp(- 0.5_r8 * dist_2 / theta_bar_2) / (sqrt(2.0_r8 * PI) * theta_bar)

! If like_bar goes to 0, can't do anything, so just keep current values
! Density at current inflation value must be positive
if(like_bar <= 0.0_r8) then
   new_obs_inflate = rho_mean
   return
endif

! Next compute derivative of likelihood at this point

fac = - 0.5_r8 * sigma_o_2 * (theta_bar_2 - dist_2) &
     / (theta_bar_2**2)

like_prime  = like_bar * fac

! If like_prime goes to 0, can't do anything, so just keep current values
! We're dividing by the derivative in the quadratic equation, so this
! term better non-zero!
if(     like_prime == 0.0_r8 .OR. &
   abs(like_bar)   <= TINY(0.0_r8) .OR. &
   abs(like_prime) <= TINY(0.0_r8) ) then
   new_obs_inflate = rho_mean
   return
endif

like_ratio = like_bar / like_prime

a = 1.0_r8 - rho_mean / beta
b = like_ratio - 2.0_r8 * rho_mean
c = rho_mean**2 - like_ratio * rho_mean

! Use nice scaled quadratic solver to avoid precision issues
call solve_quadratic(a, b, c, plus_root, minus_root)

! Do a check to pick closest root
if(abs(minus_root - rho_mean) < abs(plus_root - rho_mean)) then
   new_obs_inflate = minus_root
else
   new_obs_inflate = plus_root
endif

! Do a final check on the sign of the updated factor
! Sometimes the factor can be very small (almost zero) 
! From the selection process above it can be negative
! if the positive root is far away from it. 
! As such, keep the current factor value
if(new_obs_inflate <= 0.0_r8 .OR. new_obs_inflate /= new_obs_inflate) &
   new_obs_inflate = rho_mean

end subroutine obs_linear_bayes

!-------------------------------------------------------------------------------
!>

function obs_compute_new_density(dist_2, sigma_p_2, sigma_o_2, &
     alpha, beta, rho)

! Used to update density by taking approximate gaussian product
! HMS the difference between this and adaptive_inflate_mod/enh_compute_new_density
! is the use of a different likelihood.

real(r8), intent(in) :: dist_2
real(r8), intent(in) :: sigma_p_2, sigma_o_2, rho
real(r8), intent(in) :: alpha, beta
real(r8)             :: obs_compute_new_density

real(r8) :: theta
real(r8) :: exp_prior, exp_like

exp_prior = - beta / rho

theta = sqrt(sigma_p_2 + rho * sigma_o_2)
exp_like= - 0.5_r8 * dist_2 / theta ** 2

! see note in adaptive_inflate_mod/enh_compute_new_density about
! running into unresolved external for the gamma function
obs_compute_new_density = beta**alpha / gamma(alpha) * &
                          rho**(- alpha - 1.0_r8) / &
                          (sqrt(2.0_r8 * PI) * theta) * &
                          exp(exp_like + exp_prior)

end function obs_compute_new_density


!-------------------------------------------------------------------------------
!>
! logicals called from filter to determine when to call above functions

! ccheck if these are called before handle is init
function do_variance_estimation(estimation_handle)

  logical                               :: do_variance_estimation
  type(obs_estimation_type), intent(in) :: estimation_handle
  integer                               :: estimation_flavor

  estimation_flavor = estimation_handle%obs_estimation_flavor

  if(estimation_flavor /= NO_ESTIMATION) then
     do_variance_estimation = .true.
  else
     do_variance_estimation = .false.
  endif

end function do_variance_estimation

function use_variance_estimates(estimation_handle)

  type(obs_estimation_type), intent(in) :: estimation_handle
  logical                               :: use_variance_estimates

  use_variance_estimates = estimation_handle%use_variances

end function use_variance_estimates

function do_prior_obs_estimation(estimation_handle)

  type(obs_estimation_type), intent(in) :: estimation_handle
  logical                               :: do_prior_obs_estimation
  integer                               :: estimation_flavor

  estimation_flavor = estimation_handle%obs_estimation_flavor

  if(estimation_flavor == OB_STATE_VAR_ESTIMATION .or. estimation_flavor == BAYES_INFLATE_ESTIMATION) then
     do_prior_obs_estimation = .true.
  else
     do_prior_obs_estimation = .false.
  end if


end function do_prior_obs_estimation

function do_posterior_obs_estimation(estimation_handle)

  type(obs_estimation_type), intent(in) :: estimation_handle
  logical                               :: do_posterior_obs_estimation
  integer                               :: estimation_flavor

  estimation_flavor = estimation_handle%obs_estimation_flavor

  if(estimation_flavor == OA_OB_ESTIMATION) then
     do_posterior_obs_estimation = .true.
  else
     do_posterior_obs_estimation = .false.
  end if

end function do_posterior_obs_estimation

function get_subset_variances(estimation_handle)

  type(obs_estimation_type), intent(in) :: estimation_handle
  real(r8)                              :: get_subset_variances(MAX_OBS_ESTIMATION_SUBSETS)

  get_subset_variances = estimation_handle%current_variances

end function get_subset_variances

subroutine set_subset_variances(estimation_handle, variances)

  type(obs_estimation_type), intent(inout) :: estimation_handle
  real(r8),                  intent(in)    :: variances(:)

  estimation_handle%current_variances = variances

end subroutine set_subset_variances


!------------------------------------------

  
end module obs_estimation_mod
