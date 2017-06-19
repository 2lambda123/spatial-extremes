library(tidyverse)
library(rrfields)
library(rstan)
options(mc.cores = min(c(4L, parallel::detectCores())))
library(ggsidekick) # devtools::install_github("seananderson/ggsidekick")
library(assertthat)

# ------------------------------------------------------------
# Pick reasonable values:
if (interactive()) {
  library(manipulate)
  manipulate({
    set.seed(seed)
    simulation_data <- sim_rrfield(df = df, n_data_points = 50, seed = NULL,
      n_draws = 6, n_knots = 7, gp_scale = gp_scale, gp_sigma = gp_sigma,
      obs_error = "gamma", sd_obs = CV)
    print(simulation_data$plot)
  }, gp_scale = slider(0.05, 10, 1, step = 0.25),
    gp_sigma = slider(0.05, 10, 0.5, step = 0.25),
    df = slider(2, 50, 4, step = 1),
    CV = slider(0.01, 1, 0.05, step = 0.05),
    seed = slider(1, 300, 10, step = 1))
}

# ------------------------------------------------------------
# Now run across multiple arguments

i <<- 0

sim_fit <- function(n_draws, df = 2, n_knots = 30, gp_scale = 0.5, sd_obs = 0.2,
  comment = "", gp_sigma = 0.5, n_data_points = 50) {

  i <<- i + 1
  message(i)

  s <- sim_rrfield(df = df, n_data_points = n_data_points, seed = NULL,
    n_draws = n_draws, n_knots = n_knots, gp_scale = gp_scale,
    gp_sigma = gp_sigma, sd_obs = sd_obs, obs_error = "gamma")

  fit_model <- function(iter) {
    rrfield(y ~ 0, data = s$dat, time = "time", lon = "lon", lat = "lat",
      nknots = n_knots,
      station = "station_id",
      chains = 4L, iter = iter, obs_error = "gamma",
      prior_gp_scale = half_t(3, 0, 3),
      prior_gp_sigma = half_t(3, 0, 3),
      prior_sigma = half_t(3, 0, 3),
      prior_intercept = student_t(1e6, 0, 1),
      prior_beta = student_t(1e6, 0, 1))
  }

  m <- fit_model(iter = 500L)
  b <- broom::tidyMCMC(m$model, rhat = TRUE, ess = TRUE)
  if (any(b$ess < 100) | any(b$rhat > 1.05)) {
    m <- fit_model(iter = 2000L)
  }

  b <- broom::tidyMCMC(m$model,
    estimate.method = "median") %>%
    dplyr::select(-std.error) %>%
    tidyr::spread(term, estimate)
  names(b) <- paste0(names(b), "_est")
  b <- select(b, -starts_with("spatialEffectsKnots"))
  names(b) <- sub("\\[1\\]", "", names(b))

  b2 <- broom::tidyMCMC(m$model,
    estimate.method = "median", rhat = TRUE, ess = TRUE) %>%
    summarise(rhat = max(rhat), ess = min(ess))

  data.frame(b, b2)
}

set.seed(123)
# arguments <- readxl::read_excel("simulationTesting/simulation-arguments.xlsx")
# arguments$count <- 5L
# arguments <- arguments[rep(seq_len(nrow(arguments)), arguments$count), ]
# arguments_apply <- dplyr::select(arguments, -count, -case)
# nrow(arguments)

arguments <- expand.grid(
  df = c(2.5, 5, 20),
  n_knots = 15,
  n_draws = c(5, 15, 25),
  gp_scale = 1,
  gp_sigma = 1,
  sd_obs = c(0.1, 0.6, 1.2)
)
nrow(arguments)
arguments$count <- 100L
arguments <- arguments[rep(seq_len(nrow(arguments)), arguments$count), ]
arguments_apply <- dplyr::select(arguments,-count)
nrow(arguments_apply)

out <- plyr::mdply(arguments_apply, sim_fit)
saveRDS(out, file = "simulationTesting/mvt-norm-sim-testing2.rds")

out <- readRDS("simulationTesting/mvt-norm-sim-testing2.rds")

assert_that(max(out$rhat) < 1.05)
nrow(filter(out, rhat >= 1.05))
nrow(filter(out, rhat >= 1.10))
assert_that(min(out$ess) > 100)
nrow(filter(out, ess <= 100))

out_summary <- data.frame(out) %>%
  filter(rhat < 1.05, ess > 100) %>%
  select(-rhat, -ess)

out_summary <- mutate(out_summary, df_lab = paste0("nu==", df),
  df_lab = factor(df_lab, levels = c("nu==20", "nu==5", "nu==2.5")))

out_summary <- mutate(out_summary, n_draws_lab = paste0("Time~steps==", n_draws),
  n_draws_lab = factor(n_draws_lab, levels = c("Time~steps==25",
      "Time~steps==15", "Time~steps==5")))

ggplot(out_summary, aes(sd_obs, df_est, group = sd_obs, fill = as.factor(df))) +
  facet_grid(df_lab~n_draws_lab, labeller = label_parsed) + theme_sleek() +
  geom_violin(colour = NA) +
  geom_jitter(colour = "#00000020", height = 0, width = 0.03, cex = 1) +
  geom_hline(aes(yintercept = df), colour = "grey50", lty = 2) +
  scale_fill_brewer(palette = "YlOrRd", direction = -1) +
  ylab(expression(Estimated~nu)) +
  guides(fill = FALSE) +
  xlab("Observation error CV") +
  scale_x_continuous(breaks = unique(out_summary$sd_obs))
ggsave("figs/sim-recapture.pdf", width = 7, height = 5)

# ggplot(out_summary, aes(sd_obs, log(df_est/df), group = sd_obs, fill = as.factor(df))) +
#   facet_grid(df~n_draws) + theme_sleek() +
#   geom_violin(colour = NA) +
#   geom_jitter(colour = "#00000020", height = 0, width = 0.02) +
#   # geom_hline(aes(yintercept = df), colour = "grey50") +
#   scale_fill_brewer(palette = "YlOrRd", direction = -1)

transformation <- I
filter(out_summary, sd_obs == 0.1) %>%
  ggplot(aes(n_draws, transformation(df_est), group = n_draws, fill = as.factor(df))) +
  facet_grid(~df_lab, labeller = label_parsed) + theme_sleek() +
  geom_violin(colour = NA, alpha = 1) +
  geom_jitter(colour = "#00000040", height = 0, width = 0.7, cex = 1) +
  scale_fill_brewer(palette = "YlOrRd", direction = -1) +
  guides(fill = FALSE) +
  ylab(expression(Estimated~nu)) +
  geom_hline(aes(yintercept = transformation(df)), colour = "grey50", lty = 2) +
  xlab("Number of time steps")
ggsave("figs/sim-recapture-small.pdf", width = 5, height = 2.6)

# Try a three-part figure showing 3 dimensions one per panel

col <- RColorBrewer::brewer.pal(3, "Blues")[3]
plot_panel <- function(dat, x, xlab = "", jitter = 0.1, fill = "as.factor(df)") {
  ggplot(dat, aes_string(x, "df_est", group = x)) +
  geom_violin(colour = NA, alpha = 1, fill = col) +
  geom_jitter(colour = "#00000020", height = 0, width = jitter, cex = 0.7) +
  scale_fill_brewer(palette = "YlOrRd", direction = -1) +
  guides(fill = FALSE) +
  scale_y_continuous(breaks = c(2, 10, 20, 30), limits = c(1, 32)) +
  ylab(expression(Estimated~nu)) +
  geom_hline(aes(yintercept =(df)), colour = "grey50", lty = 2) +
  xlab(xlab)
}

g1 <- plot_panel(filter(out_summary, df == "2.5", n_draws == 25),
  "as.factor(sd_obs)", "Observation error CV", jitter = 0.1,
  fill = "as.character('red')")

g2 <- plot_panel(filter(out_summary, sd_obs == "0.1", n_draws == 25),
  "as.factor(df)", "Degrees of freedom parameter", jitter = 0.1,
  fill = "as.character('red')")
# g2 <- g2 + geom_text)

g3 <- plot_panel(filter(out_summary, sd_obs == "0.1", df == 2.5),
  "as.factor(n_draws)", "Number of times steps", jitter = 0.1,
  fill = "as.character('red')")

pdf("figs/recapture-3.pdf", width = 7, height = 2.6)
gridExtra::grid.arrange(g2, g3, g1, ncol = 3)
dev.off()

# --------------------
# Make a version with base graphics 
library("beanplot")

axis_col <- "grey55"
cols <- RColorBrewer::brewer.pal(3, "YlOrRd")

plot_panel_base <- function(d, x, hlines = 2.5, col = rep(cols[[3]], 3), x_vals = c(1, 2, 3)) {
  col <- paste0(col, "")
  plot(1, 1, xlim = c(.6, 3.4), ylim = c(2, 30), type = "n",
    axes = FALSE, ann = FALSE, yaxs = "i")
  abline(h = hlines, lty = 2, col = "grey65")
  beanplot(as.formula(paste0("df_est ~ ", x)), data = d, what = c(0,1,0,0),
    log = "", col = list(col[1], col[2], col[3]), border = NA,
    add = TRUE, axes = FALSE, cutmin = 2)
  points(jitter(as.numeric(as.factor(d[,x])), amount = 0.09), d$df_est,
    col = "#00000020", cex = 0.8, pch = 20)
  axis(1, at = 1:3, labels = x_vals, col.axis = axis_col, col = axis_col, col.ticks = axis_col, las = 1)
  box(col = axis_col)
}

margin_line <- 1.5
margin_color <- "grey45"
pdf("figs/recapture-3-base.pdf", width = 7, height = 2.6)
par(mfrow = c(1, 3), mar = c(0, 0, 1, 0), oma = c(3, 4, 0, 1),
  cex = 0.8, tcl = -0.2, mgp = c(2, 0.4, 0))
filter(out_summary, sd_obs == "0.1", n_draws == 25) %>%
  plot_panel_base("df", hlines = c(2.5, 5, 20), col = rev(cols), x_vals = c(2.5, 5, 20))
mtext("Degrees of freedom parameter", 1, col = margin_color, line = margin_line, cex = 0.8)
mtext(expression(Estimated~nu), 2, col = margin_color, line = margin_line +1, cex = 0.8)
mtext("(MVT degrees of freedom parameter)   ", 2, col = margin_color, line = margin_line, cex = 0.8)
axis(2, col = axis_col, col.ticks = axis_col, las = 1, col.axis = axis_col, at = c(2, 10, 20, 309))
x_text <- 0.5
cex_text <- 0.9
text(x_text, 28, "(a)", pos = 4, cex = cex_text, col = margin_color)
text(x_text, 25, "Obs. CV = 0.1", pos = 4, cex = cex_text, col = margin_color)
text(x_text, 23, "25 time steps", pos = 4, cex = cex_text, col = margin_color)

filter(out_summary, sd_obs == "0.1", df == 2.5) %>%
  plot_panel_base("n_draws", x_vals = c(5, 15, 25))
mtext("Number of time steps", 1, col = margin_color, line = margin_line, cex = cex_text)
text(x_text, 28, "(b)", pos = 4, cex = cex_text, col = margin_color)
# text(x_text, 27, expression(nu==2.5), pos = 4, cex = cex_text, col = margin_color)
text(x_text, 25, "Obs. CV = 0.1", pos = 4, cex = cex_text, col = margin_color)

filter(out_summary, df == "2.5", n_draws == 25) %>%
  plot_panel_base("sd_obs", x_vals = c(0.1, 0.6, 1.2))
text(x_text, 28, "(c)", pos = 4, cex = cex_text, col = margin_color)
text(x_text, 25, "25 time steps", pos = 4, cex = cex_text, col = margin_color)
# text(x_text, 27, expression(nu==2.5), pos = 4, cex = cex_text, col = margin_color)
mtext("Observation error CV", 1, col = margin_color, line = margin_line, cex = 0.8)
dev.off()


1
# filter(out_summary, CV_est < 100) %>%
# ggplot(aes(sd_obs, CV_est, group = sd_obs, fill = as.factor(df))) +
#   facet_grid(df~n_draws) + theme_sleek() +
#   geom_violin(colour = NA) +
#   geom_jitter(colour = "#00000020", height = 0, width = 0.02) +
#   # geom_hline(aes(yintercept = df), colour = "grey50") +
#   scale_fill_brewer(palette = "YlOrRd", direction = -1)
# # ggsave("figs/sim-recapture.pdf", width = 10, height = 7)

# plot_viol <- function(term, term_true) {
#   x <- tidyr::gather(out_summary, parameter, estimate, -df, -n_knots, -n_draws,
#     -gp_scale, -sd_obs, -gp_sigma) %>%
#     filter(parameter == term)
#
#   ggplot(x, aes(paste(comment, case), estimate)) +
#     geom_violin(draw_quantiles = c(0.5), trim = TRUE, fill = "grey93") +
#     coord_flip() +
#     geom_point(aes_string(y = term_true), colour = "red", size = 2) +
#     theme_sleek() +
#     labs(title = term_true, x = "")
# }
#
# p1 <- plot_viol("df_est", "df")
# p2 <- plot_viol("gp_scale_est", "gp_scale")
# p3 <- plot_viol("gp_sigma_est", "gp_sigma")
# p4 <- plot_viol("sigma_est", "sd_obs")
#
# pdf("simulationTesting/sim-mvt-norm-pars.pdf", width = 7, height = 6)
# gridExtra::grid.arrange(p1, p2, p3, p4, nrow = 2)
# dev.off()