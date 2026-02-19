library(rvest)
library(dplyr)
library(nanoparquet)

url <- "https://www.hnd.bayern.de/pegel/iller_lech/lindau-20001001/tabelle?methode=seewasserstand&begin=01.01.2023&setdiskr=15"
lake_constance_zero <- 391.84
tz <- "Europe/Berlin"

# read in old -------------------------------------------------------------

old_levels <- read_parquet("water_level.parquet") |>
  mutate(date = as.POSIXct(date, tz = tz, format = "%d.%m.%Y %H:%M")) |>
  arrange(date)

# read in new -------------------------------------------------------------

new_levels <- read_html(url) |>
  html_table(dec = ",") %>%
  `[[`(1) |>
  setNames(c("date", "water_level_m_nhn")) |>
  mutate(date = as.POSIXct(date, tz = tz, format = "%d.%m.%Y %H:%M")) |>
  filter(!is.na(date)) |>
  summarize(water_level_m_nhn = mean(water_level_m_nhn),
            .by = date) |>
  mutate(water_level_cm_lake = (water_level_m_nhn - lake_constance_zero) * 100) |>
  mutate(water_level_cm_lake = as.integer(water_level_cm_lake))

print("Start:")
print(new_levels |> head(2))
print("End:")
print(new_levels |> tail(2))

# merge -------------------------------------------------------------------

levels <- old_levels |>
  bind_rows(
    anti_join(new_levels |> arrange(date), old_levels)
  )

duplicates <- levels |> group_by(date) |> filter(n() > 1)
message("duplicates: ", duplicates |> pull(date))

unique_dates <- levels$date |> unique() |> length()
rows_levels <- nrow(levels)
if(unique_dates != rows_levels){
  message("Rows old levels:", nrow(old_levels), "\nRows new:", nrow(new_levels))
  message("Unique dates: ", unique_dates, "\n Level nrows: ", rows_levels)
  stop("Dates are not unique")
  }

# export ------------------------------------------------------------------

write_parquet(levels, "water_level.parquet")
