#!/usr/bin/env ruby

require 'yaml'
require 'open-uri'
require 'json'
require 'minitest/autorun'

API_KEY="org.onebusaway.iphone"
BASE_URL="http://localhost:8080/api/where"

SERVICES = {
  dash: {
    agency_id: '1',
    route_id: '1_35',
    stop_id: '1_512',
    lat: 38.83334,
    lon: -77.09186,
    route_min_count: 10
  },
  raba: {
    agency_id: '25',
    route_id: '25_24',
    stop_id: '25_2000',
    lat: 40.3061885,
    lon: -122.121985,
    search_radius: 20_000,
    route_min_count: 10
  },
  sdmts: {
    agency_id: 'MTS',
    route_id: 'MTS_992',
    stop_id: 'MTS_60499',
    lat: 32.899853,
    lon: -116.731188,
    route_min_count: 100,
    search_radius: 20_000,
    agencies_count: 4
  },
  sta: {
    agency_id: 'STA',
    route_id: 'STA_63',
    stop_id: 'STA_CONC',
    lat: 47.622782,
    lon: -117.390875,
    route_min_count: 50
  },
  tampa: {
    agency_id: '1',
    route_id: '1_10',
    stop_id: '1_4340',
    lat: 27.950712,
    lon: -82.397875,
    route_min_count: 30,
    agencies_count: 2
  },
  unitrans: {
    agency_id: 'unitrans',
    route_id: 'unitrans_O',
    stop_id: 'unitrans_22102',
    lat: 38.555308,
    lon: -121.73599,
    route_min_count: 20
  }
}

def call_api(endpoint, params = {})
  url = "#{BASE_URL}/#{endpoint}?key=#{API_KEY}"
  url += "&#{URI.encode_www_form(params)}" unless params.empty?
  response = URI.open(url).read
  JSON.parse(response)
end

def service_name
  compose = YAML.load_file(File.join(__dir__, '..', 'docker-compose.yaml'))
  compose.dig('services', 'oba_app', 'build', 'dockerfile').split('.').last.to_sym
end

def load_data
  service = SERVICES[service_name]
  raise "Service not found: #{service_name}" unless service
  service
end

puts "Running API tests for service: #{service_name}"

class ApiTests < Minitest::Test
  def setup
    @service = load_data
  end

  def test_current_time
    response = call_api("current-time.json")
    assert_equal(200, response["code"])
    assert_match(/\d+/, response["currentTime"].to_s)
  end

  def test_agencies_with_coverage
    response = call_api("agencies-with-coverage.json")
    agencies = response.dig('data', 'list')
    assert_equal(@service[:agencies_count] || 1, agencies.length)
    agency = agencies.filter {|a| a['agencyId'] == @service[:agency_id] }.first
    assert_in_delta(@service[:lat], agency['lat'])
    assert_in_delta(@service[:lon], agency['lon'])
  end

  def test_routes_for_agency
    response = call_api("routes-for-agency/#{@service[:agency_id]}.json")
    routes = response.dig('data', 'list')
    assert_operator(@service[:route_min_count], :<, routes.length)
    route = routes.first
    assert_equal(@service[:agency_id], route['agencyId'])
    refute_empty(route['nullSafeShortName'])
  end

  def test_stops_for_route
    response = call_api("stops-for-route/#{@service[:route_id]}.json")
    entry = response.dig('data', 'entry')
    assert_equal(["polylines", "routeId", "stopGroupings", "stopIds"], entry.keys)
    assert_equal(@service[:route_id], entry['routeId'])
  end

  def test_stop
    response = call_api("stop/#{@service[:stop_id]}.json")
    data = response.dig('data', 'entry')
    assert_equal(@service[:stop_id], data['id'])
  end

  def test_stops_for_location
    params = {lat: @service[:lat], lon: @service[:lon]}
    if @service[:search_radius]
      params[:radius] = @service[:search_radius]
    end
    response = call_api("stops-for-location.json", params)
    assert_operator(0, :<, response.dig('data', 'list').count)
  end

  def test_arrivals_and_departures_for_stop
    response = call_api("arrivals-and-departures-for-stop/#{@service[:stop_id]}.json")
    data = response.dig('data', 'entry', 'arrivalsAndDepartures')

    departures = data.collect {|d| d['predictedDepartureTime'] }.compact.select {|d| d > 0 }
    assert_operator(0, :<, departures.count, 'has real time data')
  end
end
