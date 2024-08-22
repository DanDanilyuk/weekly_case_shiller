# Date should Correlate to these:
# https://fred.stlouisfed.org/series/MEHOINUSA646N
# https://fred.stlouisfed.org/series/CSUSHPISA

# READ: https://www.calculatedriskblog.com/p/weekly-schedule.html
# INSPIRATION: https://www.longtermtrends.net/home-price-median-annual-income-ratio/
# Look at FRED Gem: https://github.com/jwarykowski/fredapi

# Total workers tables: https://www.bls.gov/news.release/wkyeng.t01.htm
# Average weekly payrolls charts: https://www.bls.gov/news.release/empsit.t19.htm
# Average weekly payrolls data: https://data.bls.gov/pdq/SurveyOutputServlet

# Employed full-time wage and salary workers: https://data.bls.gov/pdq/SurveyOutputServlet
require 'net/http'
require 'json'
require 'uri'
require 'date'
require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: weekly_case_schiller.rb [options]"

  opts.on("-b", "--bls-api-key KEY", "BLS API Key") do |key|
    options[:bls_api_key] = key
  end

  opts.on("-f", "--fred-api-key KEY", "FRED API Key") do |key|
    options[:fred_api_key] = key
  end

  opts.on("-s", "--start-date DATE", "Start Date") do |date|
    options[:start_date] = Date.parse(date)
  end
end.parse!

BLS_API_KEY = options[:bls_api_key]
FRED_API_KEY = options[:fred_api_key]
START_DATE = options[:start_date] || (Date.today - (10 * 365))

def fetch_bls_data
  url = URI.parse('https://api.bls.gov/publicAPI/v2/timeseries/data/')
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(url.path)
  request.set_form_data({
    'seriesid' => 'CES0500000011',
    'startyear' => START_DATE.year.to_s,
    'endyear' => Date.today.year.to_s,
    'registrationkey' => BLS_API_KEY,
    'count' => '100',
    'sortby' => 'asc'
  })

  response = http.request(request)
  JSON.parse(response.body)
end

def normalize_weekly_income_data(weekly_income_data)
  start_date = (START_DATE - Date.today.mday + 1)
  date_10_years_ago = (Date.today) << 12 * 10
  start_date = Date.new(date_10_years_ago.year, date_10_years_ago.month, 1)

  weekly_income_date_normalized = []
  weekly_income_data['Results']['series'][0]['data'].reverse.each do |data|
    data_date = Date.parse("#{data['year']}-#{data['periodName']}-01")
    next if data_date < start_date

    weekly_income_date_normalized << { date: data_date.to_s, value: data['value'], footnotes: data['footnotes'] }
  end

  weekly_income_date_normalized
end

def fetch_schiller_data
  series_id = 'CSUSHPINSA'
  url = URI("https://api.stlouisfed.org/fred/series/observations")
  params = {
    series_id: series_id,
    api_key: FRED_API_KEY,
    file_type: 'json',
    observation_start: START_DATE.strftime("%Y-%m-%d"),
    observation_end: Date.today.strftime("%Y-%m-%d")
  }
  url.query = URI.encode_www_form(params)

  response = Net::HTTP.get(url)
  JSON.parse(response)
end

def fetch_mortgage_data
  mortgage_series_id = 'MORTGAGE30US'
  mortgage_url = URI("https://api.stlouisfed.org/fred/series/observations")
  mortgage_params = {
    series_id: mortgage_series_id,
    api_key: FRED_API_KEY,
    file_type: 'json',
    observation_start: START_DATE.strftime("%Y-%m-%d"),
    observation_end: Date.today.strftime("%Y-%m-%d"),
    frequency: 'm'
  }
  mortgage_url.query = URI.encode_www_form(mortgage_params)

  mortgage_response = Net::HTTP.get(mortgage_url)
  JSON.parse(mortgage_response)
end

def calculate_total_costs(schiller_data, mortgage_data, weekly_income_date_normalized)
  total_costs_single = []
  total_costs_household = []
  mortgage_data['observations'].each_with_index do |mortgage_observation, i|
    schiller_observation = schiller_data['observations'][i]
    next unless schiller_observation

    schiller_price = schiller_observation['value'].to_f * 1000
    mortgage_rate = mortgage_observation['value'].to_f
    interest_rate = mortgage_rate / 100.0
    monthly_interest_rate = interest_rate / 12.0
    loan_term_months = 30 * 12

    monthly_payment = (schiller_price * monthly_interest_rate) / (1 - (1 + monthly_interest_rate)**(-loan_term_months))
    total_cost = monthly_payment * loan_term_months

    weekly_income = weekly_income_date_normalized[i][:value].to_f
    yearly_income = weekly_income * 52
    household_income = yearly_income * 1.4

    total_costs_single << { type: 'single', date: mortgage_observation['date'], total_cost: total_cost.to_i, single_income: yearly_income.to_i, income_schiller_index: (total_cost / yearly_income).round(3), schiller_price: schiller_price.to_i, mortgage_rate: mortgage_rate.round(3) }
    total_costs_household << { type: 'household', date: mortgage_observation['date'], total_cost: total_cost.to_i, household_income: household_income.to_i, income_schiller_index: (total_cost / household_income).round(3), schiller_price: schiller_price.to_i, mortgage_rate: mortgage_rate.round(3) }
    # total_costs << { date: mortgage_observation['date'], total_cost: total_cost, household_income: household_income, income_schiller_index: (total_cost / household_income), schiller_price: schiller_price}
    # total_costs << { date: mortgage_observation['date'], income_schiller_index: (total_cost / household_income).round(3), mortgage_rate: mortgage_rate }
    # total_costs << { date: mortgage_observation['date'], inc_sch_index: (total_cost / household_income).round(3), mo_rate: mortgage_rate }
  end
  total_costs = total_costs_single + total_costs_household

  total_costs
end

def print_total_costs(total_costs)
  total_costs.each do |total_cost|
    puts total_cost
  end
end

weekly_income_data = fetch_bls_data
# REFERENCE: https://fred.stlouisfed.org/series/MEHOINUSA646N
# Normalize Weekly income to get cleaner data
# Reverse the data so it's in ascending order then add a date field "date"=>"2023-11-01"
weekly_income_date_normalized = normalize_weekly_income_data(weekly_income_data)
# Process the FRED data as needed
# The series ID for the Case-Shiller Home Price Index
schiller_data = fetch_schiller_data
# Calculate the total cost of a 30-year mortgage for each month
# Reference the following doc for formulas: https://www.nar.realtor/research-and-statistics/housing-statistics/housing-affordability-index/methodology
mortgage_data = fetch_mortgage_data
total_costs = calculate_total_costs(schiller_data, mortgage_data, weekly_income_date_normalized)
print_total_costs(total_costs)
