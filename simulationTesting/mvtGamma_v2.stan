# model for presence-absence data
data {
  int<lower=1> nKnots;
  int<lower=1> nLocs;
  int<lower=1> N;
  int<lower=1> nT;
  real y[N];
  int location[N];
  matrix[nKnots,nKnots] distKnotsSq;
  matrix[nLocs,nKnots] distKnots21Sq;
}
parameters {
  real<lower=0> gp_scale;
  real<lower=0> gp_sigmaSq;
  real<lower=0> jitter_sq;
  real<lower=0> scaledf;
  real<lower=0> gammaA;
  vector[nKnots] spatialEffectsKnots[nT];
}
transformed parameters {
	vector[(nKnots)] muZeros;
	for(i in 1:nKnots) {
		muZeros[i] = 0;
	}
}
model {
  matrix[nKnots, nKnots] SigmaKnots;
  matrix[nKnots, nKnots] SigmaKnots_chol;
  matrix[nLocs,nKnots] SigmaOffDiag;
  vector[nLocs] spatialEffects[nT];
  matrix[nKnots, nKnots] invSigmaKnots;

  SigmaKnots = gp_sigmaSq * exp(-gp_scale * distKnotsSq);# cov matrix between knots
  SigmaOffDiag = gp_sigmaSq * exp(-gp_scale * distKnots21Sq);# cov matrix between knots and projected locs
  for (i in 1:nKnots) {
	SigmaKnots[i,i] = jitter_sq + gp_sigmaSq; # diagonal
	SigmaOffDiag[i,i] = jitter_sq + gp_sigmaSq; # diagonal
  }
  invSigmaKnots = inverse(SigmaKnots); # inverse needed for calculation below, this is different than inverse() in that Sigma = symm pos def

  # Calculate the random effect and projection for each time interval
  # project onto new locations (n x knots) * (knots x knots) * (knots x 1)
  #SigmaKnots_chol = cholesky_decompose(SigmaKnots);
  #spatialEffectsKnots[1] ~ multi_normal_cholesky(muZeros,SigmaKnots_chol);
  #scaledf ~ chi_square(3);
  #spatialEffects[1] = SigmaOffDiag * invSigmaKnots * (spatialEffectsKnots[1] * sqrt(3/scaledf));

  # use multivariate t dist (Ben Goodrich et al frown on this approach)
  spatialEffectsKnots[1] ~ multi_student_t(3, muZeros, SigmaKnots);
  spatialEffects[1] = SigmaOffDiag * invSigmaKnots * (spatialEffectsKnots[1] );

  # priors on parameters for covariances, etc
  gp_scale ~ cauchy(0,5);
  gp_sigmaSq ~ cauchy(0,5);
  jitter_sq ~ cauchy(0,5);
  gammaA ~ cauchy(0,5);
  for(n in 1:N) {
	  y[n] ~ gamma(gammaA, gammaA/exp(fmin(spatialEffects[1, location[n]], 200)));
  }

}