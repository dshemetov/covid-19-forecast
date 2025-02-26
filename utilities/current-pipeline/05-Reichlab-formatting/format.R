#-----------------------------------------------------#
# This file contains functions that (re)format
# data objects --- such as scorecards, prediction_cards, etc ---
# that are commonly produced by all forecasters.
#-----------------------------------------------------#

format_predictions_cards_for_reichlab_submission <- function(predictions_cards, is_case = FALSE)
{
  # Take a bunch of predictions cards, and put them in the right format
  # for submission to the CDC competition.
  # 
  # Inputs:
  #
  #  predictions_cards: a list of prediction cards with the
  #    same forecast date, and each for a different forecasting task.
  #    A predictions card is created by the 
  #    function get_predictions_card.
  #
  #  team_name: a string, what name you would like for your team
  #
  #  model_name: a string, what name you would like for your model
  #
  #  
  
  # (1) Checks
  
  ## (A) Remove non-predictions
  predictions_cards =
    predictions_cards[!is.na(predictions_cards)]
  predictions_cards =
    predictions_cards[!(predictions_cards %>% map_int(nrow) == 0)]
  if (length(predictions_cards) == 0) {
    stop("All prediction cards are either NA or empty.")
  }
  
  ## (B) Check to make sure
  ##   -- first, all predictions cards have the same forecast date
  ##   -- second, all predictions cards are for different forecasting tasks
  attribs <- predictions_cards %>% map(attributes)
  if (attribs %>% map_lgl(~ length(.x) == 0) %>% any)
    stop("At least one predictions_card is missing attributes.")
  if (attribs %>% map_lgl(~ !("call_args" %in% names(.x))) %>% any)
    stop("At least one predictions_card is missing the call_args attribute.")
  call_args <- attribs %>% map("call_args")
  task_params <- c("response", "incidence_period", "ahead", "geo_type",
                   "n_locations", "forecast_date") 
  if(call_args %>% map_lgl(~ !all(task_params %in% names(.x))) %>% any)
    stop("At least one predictions_card's call_args attribute has missing info.")
  forecast_dates <- do.call("c", call_args %>% map("forecast_date"))
  params <- call_args %>% map(~ list_modify(.x, "forecast_date" = NULL))
  if(length(unique(forecast_dates)) > 1)
    stop("Each prediction card must be for the same forecast date.")
  if(length(unique(params)) != length(params))
    stop("Each prediction card must be for a separate forecasting task.")
  
  # (2) Reformat each prediction card
  reichlab_prediction_cards <- map2(predictions_cards,params, 
               ~format_prediction_card_for_reichlab_submission(.x,.y))
  
  # (3) Combine all prediction cards into a single data frame with an additional
  #     column called forecast_date.
  reichlab_predicted <- bind_rows(reichlab_prediction_cards)
  
  # if the predictions are case level then reduce quantiles to allowed
  #
  if (is_case) {
    quant_allowed <- c(0.025, 0.100, 0.250, 0.500, 0.750, 0.900, 0.975)
    reichlab_predicted <- reichlab_predicted %>% 
      filter(quantile %in% quant_allowed | type == "point")
  }  
  
  return(reichlab_predicted)
}

format_prediction_card_for_reichlab_submission <- function(prediction_card,
                                                            param)
{
  # Inputs:
  # 
  #   prediction_card: A predictions card is created by the 
  #    function get_predictions_card.
  # 
  #   param: A list containing
  #      response, incidence_period, ahead, geo_type,n_locations
  #
  
  # (1) Isolate necessary parameters
  stopifnot(length(unique(prediction_card %>% pull(forecast_date))) == 1)
  response <- param[["response"]]
  ahead <- param[["ahead"]]
  incidence_period <- param[["incidence_period"]]
  forecast_date <- (prediction_card %>% pull(forecast_date))[1]
  
  # (2) Put quantiles into properly formatted data frame.
  param_df <-  tibble(
    target = rename_response_for_reichlab(param[["response"]],
                                          param[["ahead"]],
                                          param[["incidence_period"]]),
    target_end_date = evalforecast::get_target_period(forecast_date,incidence_period,ahead)[["end"]],
  )
  quantile_param_df <- param_df %>% mutate(type = "quantile")
  reichlab_quantile_df <- prediction_card %>% unnest(cols = forecast_distribution) %>%
    rename(quantile = probs, value = quantiles) %>%
    mutate(quantile = round(quantile, 3)) %>%
    expand_grid(quantile_param_df)
  
  # (3) Put point predictions into properly formatted data frame
  #     NOTE: We will use the median as our point predictions.
  point_param_df <- param_df %>% mutate(type = "point")
  reichlab_point_pdf <- prediction_card %>% unnest(cols = forecast_distribution) %>%
    filter(abs(probs - .5) < 1e-8) %>% # restrict ourselves to the median
    select(-probs) %>%
    rename(value = quantiles) %>%
    mutate(quantile = NA) %>%
    expand_grid(point_param_df)
  
  return(bind_rows(reichlab_quantile_df,reichlab_point_pdf))
}

rename_response_for_reichlab <- function(response,ahead,incidence_period)
{
  stopifnot(incidence_period == "epiweek")
  stopifnot(response %in% c("jhu-csse_deaths_incidence_num","usa-facts_confirmed_incidence_num","usa-facts_deaths_incidence_num"))
  if (response %in% c("jhu-csse_deaths_incidence_num","usa-facts_deaths_incidence_num")) {
     return(paste0(ahead," wk ahead inc death"))
     }
  else {
     return(paste0(ahead," wk ahead inc case"))
  }
}